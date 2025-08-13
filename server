package main

import (
	"encoding/json"
	"io"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/pion/rtp"
	"github.com/pion/webrtc/v3"
)

var (
	upgrader       = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	videoTracks    []*webrtc.TrackLocalStaticRTP
	videoTrackLock sync.RWMutex
)

// Message types for signaling
type Message struct {
	Type string      `json:"type"`
	Data interface{} `json:"data"`
}

func createPeerConnection() (*webrtc.PeerConnection, *webrtc.TrackLocalStaticRTP, error) {
	publicIP := os.Getenv("EXTERNAL_IP")
	if publicIP == "" {
		publicIP = "45.13.200.118" // Your external IP as fallback
	}

	log.Println("Using external IP for ICE:", publicIP)

	// Create a MediaEngine and register VP8 codec
	m := &webrtc.MediaEngine{}
	if err := m.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeVP8, ClockRate: 90000},
		PayloadType:        96,
	}, webrtc.RTPCodecTypeVideo); err != nil {
		return nil, nil, err
	}

	// Set ICE settings
	settingEngine := webrtc.SettingEngine{}
	settingEngine.SetEphemeralUDPPortRange(10000, 11000)

	// FIXED: Use actual external IP instead of host.docker.internal
	if net.ParseIP(publicIP) != nil {
		settingEngine.SetNAT1To1IPs([]string{publicIP}, webrtc.ICECandidateTypeHost)
		log.Printf("Set NAT1To1IP to: %s", publicIP)
	} else {
		log.Printf("Invalid external IP: %s", publicIP)
	}

	settingEngine.SetICETimeouts(20*time.Second, 10*time.Second, 2*time.Second)

	// Create API with media engine and setting engine
	api := webrtc.NewAPI(
		webrtc.WithMediaEngine(m),
		webrtc.WithSettingEngine(settingEngine),
	)

	// Create a new PeerConnection
	peerConnection, err := api.NewPeerConnection(webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{
			{
				URLs: []string{"stun:stun.l.google.com:19302"},
			},
			{
				URLs: []string{"stun:stun1.l.google.com:19302"},
			},
		},
	})
	if err != nil {
		return nil, nil, err
	}

	// Create a video track
	videoTrack, err := webrtc.NewTrackLocalStaticRTP(webrtc.RTPCodecCapability{
		MimeType: webrtc.MimeTypeVP8,
	}, "video", "pion-video")
	if err != nil {
		peerConnection.Close()
		return nil, nil, err
	}

	// Add the track to the peer connection
	rtpSender, err := peerConnection.AddTrack(videoTrack)
	if err != nil {
		peerConnection.Close()
		return nil, nil, err
	}

	// Read RTCP packets
	go func() {
		rtcpBuf := make([]byte, 1500)
		for {
			if _, _, rtcpErr := rtpSender.Read(rtcpBuf); rtcpErr != nil {
				return
			}
		}
	}()

	// Setup ICE connection monitoring
	peerConnection.OnICEConnectionStateChange(func(state webrtc.ICEConnectionState) {
		log.Printf("ICE Connection State changed: %s\n", state.String())

		if state == webrtc.ICEConnectionStateFailed || state == webrtc.ICEConnectionStateClosed {
			// Remove track from the global list when connection fails or closes
			videoTrackLock.Lock()
			for i, track := range videoTracks {
				if track == videoTrack {
					videoTracks = append(videoTracks[:i], videoTracks[i+1:]...)
					break
				}
			}
			videoTrackLock.Unlock()
		}
	})

	return peerConnection, videoTrack, nil
}

func main() {
	log.Println("Starting WebRTC server...")

	// Start RTP listener for ffmpeg stream
	go func() {
		log.Println("Starting RTP listener on port 5004...")

		// Check for SDP file
		sdpFile := "/app/stream.sdp"
		if _, err := os.Stat(sdpFile); os.IsNotExist(err) {
			log.Printf("Warning: SDP file %s not found.", sdpFile)
		} else {
			if sdpData, err := ioutil.ReadFile(sdpFile); err == nil {
				log.Printf("Using SDP: %s", string(sdpData))
			}
		}

		// Listen for RTP packets
		addr := net.UDPAddr{IP: net.ParseIP("0.0.0.0"), Port: 5004}
		conn, err := net.ListenUDP("udp", &addr)
		if err != nil {
			log.Fatal("Failed to listen on UDP: ", err)
		}
		defer conn.Close()

		log.Println("RTP listener started successfully on port 5004")

		buf := make([]byte, 1600)
		packetCounter := 0
		lastLog := time.Now()

		for {
			n, _, err := conn.ReadFromUDP(buf)
			if err != nil {
				log.Println("Error reading RTP:", err)
				continue
			}

			packetCounter++
			if time.Since(lastLog) > 5*time.Second {
				log.Printf("Received %d RTP packets in the last 5 seconds", packetCounter)
				packetCounter = 0
				lastLog = time.Now()
			}

			packet := &rtp.Packet{}
			if err := packet.Unmarshal(buf[:n]); err != nil {
				log.Println("Error unmarshaling RTP:", err)
				continue
			}

			// Forward RTP packet to all connected video tracks
			videoTrackLock.RLock()
			for _, track := range videoTracks {
				if err := track.WriteRTP(packet); err != nil && err != io.ErrClosedPipe {
					log.Println("Error writing RTP to track:", err)
				}
			}
			videoTrackLock.RUnlock()
		}
	}()

	// FIXED: Improved WebSocket handler with proper ICE candidate exchange
	http.HandleFunc("/signal", func(w http.ResponseWriter, r *http.Request) {
		log.Println("New WebSocket connection")
		ws, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Println("WebSocket upgrade failed:", err)
			return
		}
		defer ws.Close()

		// Create a new peer connection for this client
		peerConnection, videoTrack, err := createPeerConnection()
		if err != nil {
			log.Printf("Failed to create peer connection: %v", err)
			return
		}
		defer peerConnection.Close()

		// Add this track to global list for RTP forwarding
		videoTrackLock.Lock()
		videoTracks = append(videoTracks, videoTrack)
		videoTrackLock.Unlock()

		// FIXED: Handle ICE candidates
		peerConnection.OnICECandidate(func(candidate *webrtc.ICECandidate) {
			if candidate == nil {
				log.Println("ICE gathering complete")
				return
			}

			log.Printf("Generated ICE candidate: %s", candidate.String())

			msg := Message{
				Type: "ice-candidate",
				Data: candidate.ToJSON(),
			}

			if err := ws.WriteJSON(msg); err != nil {
				log.Printf("Failed to send ICE candidate: %v", err)
			}
		})

		for {
			var msg Message
			err := ws.ReadJSON(&msg)
			if err != nil {
				log.Println("WebSocket read error:", err)
				break
			}

			switch msg.Type {
			case "offer":
				// Parse the offer from the data field
				offerData, err := json.Marshal(msg.Data)
				if err != nil {
					log.Printf("Failed to marshal offer data: %v", err)
					break
				}

				var offer webrtc.SessionDescription
				if err := json.Unmarshal(offerData, &offer); err != nil {
					log.Printf("Failed to unmarshal offer: %v", err)
					break
				}

				log.Printf("Received offer SDP: %s", offer.SDP)
				log.Printf("Offer type: %s", offer.Type)

				log.Println("Received offer, setting remote description")
				if err := peerConnection.SetRemoteDescription(offer); err != nil {
					log.Printf("SetRemoteDescription failed: %v", err)
					break
				}

				log.Println("Creating answer")
				answer, err := peerConnection.CreateAnswer(nil)
				if err != nil {
					log.Printf("CreateAnswer failed: %v", err)
					break
				}

				log.Println("Setting local description")
				if err := peerConnection.SetLocalDescription(answer); err != nil {
					log.Printf("SetLocalDescription failed: %v", err)
					break
				}

				// Send the answer
				answerMsg := Message{
					Type: "answer",
					Data: answer,
				}

				log.Println("Sending answer to client")
				if err := ws.WriteJSON(answerMsg); err != nil {
					log.Printf("Failed to send answer: %v", err)
					break
				}

				log.Println("Answer sent successfully")

			case "ice-candidate":
				// Parse the ICE candidate from the data field
				candidateData, err := json.Marshal(msg.Data)
				if err != nil {
					log.Printf("Failed to marshal candidate data: %v", err)
					continue
				}

				var candidate webrtc.ICECandidateInit
				if err := json.Unmarshal(candidateData, &candidate); err != nil {
					log.Printf("Failed to unmarshal ICE candidate: %v", err)
					continue
				}

				log.Printf("Received ICE candidate: %s", candidate.Candidate)
				if err := peerConnection.AddICECandidate(candidate); err != nil {
					log.Printf("Failed to add ICE candidate: %v", err)
				}

			default:
				log.Printf("Unknown message type: %s", msg.Type)
			}
		}

		log.Println("WebSocket connection closed")
	})

	// Serve HTML page
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// You'll need to update your HTML client to handle the new message format
		w.Write([]byte(`
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC Stream</title>
</head>
<body>
    <video id="remoteVideo" autoplay playsinline controls></video>
    <script>
        const ws = new WebSocket('ws://localhost:8080/signal');
        const pc = new RTCPeerConnection({
            iceServers: [
                {urls: 'stun:stun.l.google.com:19302'},
                {urls: 'stun:stun1.l.google.com:19302'},
                {urls: 'stun:stun2.l.google.com:19302'}
            ]
        });

        // Add transceiver to receive video
        pc.addTransceiver('video', { direction: 'recvonly' });

        pc.ontrack = (event) => {
            console.log('Received track:', event.track);
            document.getElementById('remoteVideo').srcObject = event.streams[0];
        };

        pc.onicecandidate = (event) => {
            if (event.candidate) {
                console.log('Sending ICE candidate:', event.candidate.candidate);
                ws.send(JSON.stringify({
                    type: 'ice-candidate',
                    data: {
                        candidate: event.candidate.candidate,
                        sdpMid: event.candidate.sdpMid,
                        sdpMLineIndex: event.candidate.sdpMLineIndex
                    }
                }));
            }
        };

        pc.oniceconnectionstatechange = () => {
            console.log('ICE connection state:', pc.iceConnectionState);
        };

        ws.onopen = async () => {
            console.log('WebSocket connected');
            const offer = await pc.createOffer();
            console.log('Created offer:', offer.sdp);
            await pc.setLocalDescription(offer);
            ws.send(JSON.stringify({
                type: 'offer',
                data: {
                    type: offer.type,
                    sdp: offer.sdp
                }
            }));
        };

        ws.onmessage = async (event) => {
            const msg = JSON.parse(event.data);
            console.log('Received message:', msg.type);

            if (msg.type === 'answer') {
                console.log('Setting remote description:', msg.data.sdp);
                await pc.setRemoteDescription(msg.data);
            } else if (msg.type === 'ice-candidate') {
                console.log('Adding ICE candidate:', msg.data.candidate);
                await pc.addIceCandidate(msg.data);
            }
        };

        ws.onerror = (error) => {
            console.error('WebSocket error:', error);
        };

        ws.onclose = () => {
            console.log('WebSocket closed');
        };
    </script>
</body>
</html>
        `))
	})

	log.Println("Starting HTTP server on :8080")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatal("HTTP server error: ", err)
	}
}
