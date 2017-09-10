//
//  ViewController.swift
//  MyTV
//
//  Created by Sriram bhargav Karnati on 7/15/17.
//  Copyright © 2017 Sriram bhargav Karnati. All rights reserved.
//

import ARKit
import AVFoundation
import CoreMotion
import SceneKit
import Speech
import SpriteKit
import UIKit
import YoutubeSourceParserKit

public extension String {
    func stringByReplacingFirstOccurrenceOfString(target: String, withString replaceString: String) -> String {
        if let range = self.range(of: target) {
            return self.replacingCharacters(in: range, with: replaceString)
        }
        return self
    }
}

class ViewController: UIViewController, ARSCNViewDelegate, SFSpeechRecognizerDelegate {

    
    @IBOutlet var cardboardButton: UIButton!
    @IBAction func switchCardboardView(_ sender: UIButton) {
        self.sceneView.isHidden = !self.isCardboardView
        self.leftImageView.isHidden = self.isCardboardView
        self.rightImageView.isHidden = self.isCardboardView
        self.leftSceneView.isHidden = self.isCardboardView
        self.rightSceneView.isHidden = self.isCardboardView
        self.isCardboardView = !self.isCardboardView

        if self.isCardboardView {
            self.backgroundContents = self.leftSceneView.scene.background.contents
            self.view.backgroundColor = viewBackgroundColor
            self.sceneView.debugOptions = []
        } else {
            self.sceneView.scene.background.contents = self.backgroundContents
            self.view.backgroundColor = UIColor.clear
        }
    }

    var backgroundContents:Any? = nil
    var isCardboardView:Bool = false
    var defaultBackgroundColor:UIColor!
    
    @IBOutlet var leftImageView: UIImageView!
    @IBOutlet var rightImageView: UIImageView!
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var leftSceneView: ARSCNView!
    @IBOutlet var rightSceneView: ARSCNView!
    
    @IBOutlet var microphoneButton: UIButton!

    @IBAction func microphone(_ sender: UIButton) {
        var imageName: String
        is_microphone_on = !is_microphone_on
        if (is_microphone_on) {
            imageName = "microphone_on"
            self.setLabelText(text: "Ask me")
            self.recordAndRecognizeSpeech()
        } else {
            imageName = "microphone_off"
            self.stopRecording()
        }
        sender.setImage(UIImage(named: imageName), for: UIControlState.normal)
    }

    @IBOutlet var actionText: UILabel!

    var is_microphone_on:Bool = false
    
    // Parametres
    let interpupilaryDistance = 0.066
    let viewBackgroundColor:UIColor = UIColor.white
    let eyeFOV = 60; let cameraImageScale = 3.478;
    
    var videoNode:SKVideoNode?
    var tvNode: SCNNode?
    var scene:SCNScene?
    var player:AVPlayer?
    var playerItems = [AVPlayerItem]() // your array of items
    var playerItemContext = [Int](repeating: 0, count:64)
    var isTVShown:Bool = false
    fileprivate var planes: [String : SCNNode] = [:]
    fileprivate var showPlanes: Bool = true
    var currentTrack = 0
    var speechBufferCount = 0
    
    let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    let audioEngine = AVAudioEngine()
    var audioSession:AVAudioSession?
    
    var timer:Timer?
    
    var songs = [String]()
    var lastCommand: String = ""

    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            self.microphoneButton.isEnabled = true
            self.microphoneButton.setImage(UIImage(named: "microphone_on"), for: UIControlState.normal)
            self.setLabelText(text: "")
        } else {
            self.microphoneButton.isEnabled = false
            self.microphoneButton.setImage(UIImage(named: "microphone_off"), for: UIControlState.normal)
            self.setLabelText(text: "Recognition not available")
        }
    }
    
    func setLabelText(text: String) {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 64.0
        style.headIndent = 64.0
        style.alignment = NSTextAlignment.center
        style.lineBreakMode = NSLineBreakMode.byTruncatingHead
        style.lineSpacing = 6
        style.maximumLineHeight = 24
        
        // 996633
        // red: 153.0/255, green: 102.0/255, blue: 51.0/255, alpha: 1.0
        let para = NSMutableAttributedString(string: text, attributes: [NSAttributedStringKey.paragraphStyle: style, NSAttributedStringKey.foregroundColor: UIColor.init(red: 0, green: 0, blue: 0, alpha: 1.0), NSAttributedStringKey.font: UIFont(name: "Futura-Medium", size: 24)!])
        self.actionText.attributedText = para
        self.actionText.numberOfLines = 2
    }

    func createTimer(_ interval:Double) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { (_) in
            if self.audioEngine.isRunning {
                self.recognitionTask?.finish()
            }
        }
    }

    func stopRecording() {
        if self.audioEngine.isRunning {
            self.audioEngine.stop()
            self.audioEngine.inputNode.removeTap(onBus: 0)
            self.recognitionRequest?.endAudio()
            self.recognitionRequest = nil
            self.recognitionTask?.cancel()
            self.recognitionTask = nil
            self.microphoneButton.isEnabled = true
            self.setLabelText(text: "")
        }
    }
    
    func setAudioSession() {
        audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession?.setCategory(AVAudioSessionCategoryPlayAndRecord, mode: AVAudioSessionModeVideoChat, options: [AVAudioSessionCategoryOptions.mixWithOthers])
            try audioSession?.setActive(true, with: .notifyOthersOnDeactivation)
        } catch {
            print(error)
        }
    }
    
    func recordAndRecognizeSpeech() {
        // Cancel the previous task if it's running.
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to created a SFSpeechAudioBufferRecognitionRequest object") }
        
        // Configure request so that results are returned before audio recording is finished
        recognitionRequest.shouldReportPartialResults = true
        speechRecognizer.defaultTaskHint = SFSpeechRecognitionTaskHint.search
        // A recognition task represents a speech recognition session.
        // We keep a reference to the task so that it can be cancelled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false
            if let result = result {
                // Helps in terminating speech recognition after 10 seconds of silence.
                self.createTimer(4)
                var userText:String = result.bestTranscription.formattedString
                print(userText)
                isFinal = result.isFinal
                if userText.lowercased().hasPrefix("okay tv") || userText.lowercased().hasPrefix("ok tv") {
                    userText = userText.lowercased().stringByReplacingFirstOccurrenceOfString(target: "okay tv", withString: "")
                    userText = userText.stringByReplacingFirstOccurrenceOfString(target: "ok tv", withString: "")
                    userText = userText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !result.isFinal {
                        self.microphoneButton.setImage(UIImage(named: "microphone_listening"), for: UIControlState.normal)
                    } else {
                        self.lastCommand = userText
                        self.microphoneButton.setImage(UIImage(named: "microphone_on"), for: UIControlState.normal)
                    }
                    self.setLabelText(text: userText)
                }
            }

            if error != nil || isFinal {
                print(error?.localizedDescription ?? "")
                print("completed recognition: ", result?.bestTranscription.formattedString ?? "")
                self.stopRecording()
                self.recordAndRecognizeSpeech()
                if !self.lastCommand.isEmpty {
                    self.obey()
                }
            }
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        // inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print(error)
        }
    }
    
    func obey() {
        if self.isTVShown {
            if (self.lastCommand.range(of: "next") != nil) {
                nextTrack()
            } else if (self.lastCommand.range(of: "previous") != nil || self.lastCommand.range(of: "go back") != nil) {
                previousTrack()
            } else if (self.lastCommand.range(of: "pause") != nil) {
                self.player?.pause()
            } else if (self.lastCommand.range(of: "continue") != nil || self.lastCommand.lowercased() == "play") {
                self.player?.play()
            } else if (self.lastCommand.range(of: "rewind") != nil) {
                self.player?.seek(to: CMTimeSubtract((self.player?.currentTime())!, CMTimeMakeWithSeconds(5.0, 1)))
            } else if (self.lastCommand.range(of: "fast forward") != nil) {
                self.player?.seek(to: CMTimeAdd((self.player?.currentTime())!, CMTimeMakeWithSeconds(5.0, 1)))
            } else {
                for (index, song) in songs.enumerated() {
                    if self.lastCommand.range(of: song) != nil {
                        currentTrack = index
                        playTrack()
                        self.lastCommand = ""
                        return
                    }
                }
                // Doesn't match with any ondevice content. Youtube query.
                let string = self.lastCommand
                if (string.range(of: "play ") != nil) {
                    let replaced = (string as NSString).replacingOccurrences(of: "play ", with: "")
                    print(replaced)
                    var searchURLComponents = URLComponents.init()
                    searchURLComponents.scheme = "https"
                    searchURLComponents.host = "www.googleapis.com"
                    searchURLComponents.path = "/youtube/v3/search"
                    searchURLComponents.queryItems = [
                        URLQueryItem(name: "q", value: replaced), URLQueryItem(name: "maxResults", value: "5"),
                        URLQueryItem(name: "part", value: "snippet"), URLQueryItem(name: "type", value: "video"),
                        URLQueryItem(name: "key", value: YOUTUBE_DATA_API_KEY)
                    ]
                    let searchURL = searchURLComponents.url!
                    // Create your request
                    let task = URLSession.shared.dataTask(with: searchURL, completionHandler: { (data, response, error) -> Void in
                        do {
                            var videoIds: [String] = []
                            if let jsonResult = try JSONSerialization.jsonObject(with: data!, options: []) as? [String : Any] {
                                for case let item in (jsonResult["items"] as? [[String: Any]])! {
                                    if let itemId =  item["id"] as? [String: Any] {
                                        print(itemId["videoId"]!)
                                        videoIds.append(itemId["videoId"] as! String)
                                    }
                                }
                            }
                            self.preparePlayerItemsYoutube(videoIds: videoIds)
                        }
                        catch {
                            print("json error: \(error)")
                        }
                        
                    })
                    task.resume()
                }
                
            }
            self.lastCommand = ""
        }
    }
    
    func setupCardboardViews() {
        self.leftSceneView.scene = self.scene!
        self.leftSceneView.isPlaying = true
        self.leftSceneView.showsStatistics = self.sceneView.showsStatistics
        self.rightSceneView.scene = self.scene!
        self.rightSceneView.isPlaying = true
        self.rightSceneView.showsStatistics = self.sceneView.showsStatistics
        // Setup ImageViews - for rendering Camera Image
        self.leftImageView.clipsToBounds = true
        self.leftImageView.contentMode = UIViewContentMode.center
        self.rightImageView.clipsToBounds = true
        self.rightImageView.contentMode = UIViewContentMode.center
    }
    
    func setupScene() {
        self.sceneView.delegate = self
        self.sceneView.showsStatistics = true
        self.sceneView.autoenablesDefaultLighting = true
        self.sceneView.antialiasingMode = .multisampling4X
        self.sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints,ARSCNDebugOptions.showWorldOrigin]
        scene = SCNScene()
        sceneView.scene = scene!
        
        preparePlayerItems()
        
        // Tap
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(hitHitTest))
        sceneView.addGestureRecognizer(tapGesture)
        
        // Double Tap
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(togglePlanes))
        doubleTapGesture.numberOfTapsRequired = 2
        sceneView.addGestureRecognizer(doubleTapGesture)
        
        // Swipe gestures for video
        let directions: [UISwipeGestureRecognizerDirection] = [.right, .left, .up, .down]
        for direction in directions {
            let gesture = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
            gesture.direction = direction
            sceneView.addGestureRecognizer(gesture)
        }
        self.setupCardboardViews()
    }
    
    @objc func handleSwipe(sender: UISwipeGestureRecognizer) {
        if isTVShown {
            if (sender.direction == UISwipeGestureRecognizerDirection.right) {
                previousTrack()
            } else if (sender.direction == UISwipeGestureRecognizerDirection.left) {
                nextTrack()
            }
        }
    }

    @objc func togglePlanes(sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        self.showPlanes = !self.showPlanes
        if (!self.showPlanes) {
            self.sceneView.debugOptions = []
        } else {
            self.sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints,ARSCNDebugOptions.showWorldOrigin]
        }
        self.planes.values.forEach({ NodeGenerator.update(planeNode: $0, hidden: !self.showPlanes) })
    }

    @objc func hitHitTest(sender: UITapGestureRecognizer) {
        if (self.isTVShown) { return }
        let point = sender.location(in: self.sceneView)
        let results = self.sceneView.hitTest(point, types: [.existingPlaneUsingExtent, .estimatedHorizontalPlane])
        if let match = results.first {
            guard let planeAnchor = match.anchor as? ARPlaneAnchor else { return }
            let key = planeAnchor.identifier.uuidString
            if let existingPlane = self.planes[key] {
                let tvNode = existingPlane.parent!.clone()
                // Detach tvNode from its parent.
                tvNode.removeFromParentNode()
                // Delete original detected plane.
                tvNode.enumerateChildNodes {
                    (childNode, _) in
                    childNode.removeFromParentNode()
                }
                initPlayer()
                let planeNode = SCNNode(geometry: getTV())
                planeNode.name = "tv"
                planeNode.position = SCNVector3Make(planeAnchor.center.x, -0.005, planeAnchor.center.z)
                tvNode.addChildNode(planeNode)
                tvNode.position = SCNVector3Make(tvNode.position.x, tvNode.position.y + 1, tvNode.position.z - Float(planeAnchor.extent.z)/2.0);
                self.sceneView.scene.rootNode.addChildNode(tvNode)
                self.isTVShown = true;
                self.microphoneButton.isHidden = false
                self.actionText.isHidden = false
            }
        }
    }
    
    func getSpriteScene(newPlayer: AVPlayer) -> SKScene {
        videoNode = SKVideoNode.init(avPlayer: newPlayer)
        let size = CGSize(width: 1920, height: 1080)
        videoNode?.size = size
        videoNode?.position = CGPoint(x: size.width/2.0, y: size.height/2.0)
        let spriteScene = SKScene(size: size)
        spriteScene.addChild(videoNode!)
        return spriteScene
    }
    
    func getVideoMaterial() -> SCNMaterial {
        let videomaterial = SCNMaterial()
        videomaterial.isDoubleSided = false
        videomaterial.diffuse.contents = getSpriteScene(newPlayer: player!)
        videomaterial.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(1, -1, 1), 0, 1, 0)
        return videomaterial
    }
    
    func getTV() -> SCNPlane {
        let plane = SCNPlane()
        plane.width = 1.5
        plane.height = 0.9
        plane.materials = [getVideoMaterial()]
        return plane
    }
    
    func setupUI() {
        self.defaultBackgroundColor = self.view.backgroundColor
        self.isCardboardView = false
        self.sceneView.isHidden = false
        self.leftImageView.isHidden = true
        self.rightImageView.isHidden = true
        self.leftSceneView.isHidden = true
        self.rightSceneView.isHidden = true
        self.microphoneButton.isHidden = true
        self.actionText.isHidden = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true
        self.setupUI()
        self.setAudioSession()
        self.setupScene()
        // Disable the record buttons until authorization has been granted.
        self.microphoneButton.isEnabled = false
    }

    override public func viewDidAppear(_ animated: Bool) {
        speechRecognizer.delegate = self
        
        SFSpeechRecognizer.requestAuthorization { authStatus in
            /*
             The callback may not be called on the main thread. Add an
             operation to the main queue to update the record button's state.
             */
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    self.microphoneButton.isEnabled = true
                    
                case .denied:
                    self.microphoneButton.isEnabled = false
                    self.setLabelText(text: "User denied access to speech recognition")
                    
                case .restricted:
                    self.microphoneButton.isEnabled = false
                    self.setLabelText(text: "Speech recognition restricted on this device")
                    
                case .notDetermined:
                    self.microphoneButton.isEnabled = false
                    self.setLabelText(text: "Speech recognition not yet authorized")
                }
            }
        }
    }
    
    func enableCardboardView() {
        // Set POV for both eyes.
        let leftEyePOV: SCNNode = SCNNode()
        leftEyePOV.transform = (self.sceneView.pointOfView?.transform)!
        leftEyePOV.scale = (self.sceneView.pointOfView?.scale)!
        let eyeCamera: SCNCamera = SCNCamera()
        eyeCamera.wantsExposureAdaptation = true
        eyeCamera.wantsHDR = true
        // eyeCamera.automaticallyAdjustsZRange = true
        eyeCamera.zNear = 0.0001
        // eyeCamera.zFar = 1
        eyeCamera.fieldOfView = CGFloat(eyeFOV)
        leftEyePOV.camera = eyeCamera
        self.leftSceneView.pointOfView = leftEyePOV
        
        let rightEyePOV : SCNNode = (self.leftSceneView.pointOfView?.clone())!
        // Adjust POV for Right Eye.
        let orientation : SCNQuaternion = leftEyePOV.orientation
        let orientationQuaternion : GLKQuaternion = GLKQuaternionMake(orientation.x, orientation.y, orientation.z, orientation.w)
        let eyePos : GLKVector3 = GLKVector3Make(1.0, 0.0, 0.0)
        let rotatedEyePos : GLKVector3 = GLKQuaternionRotateVector3(orientationQuaternion, eyePos)
        let rotatedEyePosSCNV : SCNVector3 = SCNVector3Make(rotatedEyePos.x, rotatedEyePos.y, rotatedEyePos.z)
        let mag : Float = Float(interpupilaryDistance)
        rightEyePOV.position.x += rotatedEyePosSCNV.x * mag
        rightEyePOV.position.y += rotatedEyePosSCNV.y * mag
        rightEyePOV.position.z += rotatedEyePosSCNV.z * mag
        self.rightSceneView.pointOfView = rightEyePOV

        // Set transparent background for all sceneViews.
        self.sceneView.scene.background.contents = UIColor.clear
        
        // Refresh camera frame.
        guard let pixelBuffer:CVPixelBuffer = self.sceneView.session.currentFrame?.capturedImage else {
            print("image not captured")
            return
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let cgImage = CIContext(options: nil).createCGImage(ciImage, from: ciImage.extent)
        // Set image orientation.
        let imageOrientation : UIImageOrientation = (UIApplication.shared.statusBarOrientation == UIInterfaceOrientation.landscapeLeft) ? UIImageOrientation.down : UIImageOrientation.up
        self.leftImageView.image = UIImage(cgImage: cgImage!, scale: CGFloat(cameraImageScale), orientation: imageOrientation)
        self.rightImageView.image = self.leftImageView.image
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if isCardboardView {
            DispatchQueue.main.async { self.enableCardboardView() }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        let key = planeAnchor.identifier.uuidString
        let planeNode = NodeGenerator.generatePlaneFrom(planeAnchor: planeAnchor, hidden: !self.showPlanes)
        node.addChildNode(planeNode)
        self.planes[key] = planeNode
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        let key = planeAnchor.identifier.uuidString
        if let existingPlane = self.planes[key] {
            NodeGenerator.update(planeNode: existingPlane, from: planeAnchor, hidden: !self.showPlanes)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        let key = planeAnchor.identifier.uuidString
        if let existingPlane = self.planes[key] {
            existingPlane.removeFromParentNode()
            self.planes.removeValue(forKey: key)
        }
    }
    
    func degToRad(deg: Float) -> Float {
        return deg / 180 * Float(Double.pi)
    }
    
    var isYoutubeAction: Bool = false
    
    func preparePlayerItemsYoutube(videoIds: [String]) {
        self.isYoutubeAction = true
        let playlistCount = self.playerItems.count
        for index in 0..<playlistCount-currentTrack-1 {
            let _ = self.playerItems.popLast()
            self.playerItemContext[playlistCount - index - 1] = 0
        }
        for videoId in videoIds {
            let videoURLString = Youtube.h264videosWithYoutubeID(youtubeID: videoId)
            if videoURLString != "" {
                self.preparePlayerItem(url: NSURL(string: videoURLString)!)
                if self.isYoutubeAction {
                    self.isYoutubeAction = false
                    nextTrack()
                }
            }
        }
    }
    
    func preparePlayerItems() {
        let videos = ["track1", "track2", "track3", "track4"]
        songs = ["can't stop the feeling", "attention", "believer", "starboy"]
        for video in videos {
            preparePlayerItem(url: NSURL(fileURLWithPath: Bundle.main.path(forResource: video, ofType:"mp4")!))
        }
    }
    
    func preparePlayerItem(url: NSURL) {
        // Create asset to be played
        let asset = AVURLAsset(url: url as URL, options: nil)
        //print(AVURLAsset.audiovisualTypes())
        
        let assetKeys = [
            "playable",
            "hasProtectedContent"
        ]
        // Create a new AVPlayerItem with the asset and an
        // array of asset keys to be automatically loaded
        playerItems.append(AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: assetKeys))
        // Register as an observer of the player item's status property
        playerItems[playerItems.count - 1].addObserver(
            self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.old, .new], context: &playerItemContext[playerItems.count - 1])
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        // Only handle observations for the playerItemContext
        guard context == &playerItemContext[currentTrack] else {
            super.observeValue(forKeyPath: keyPath,
                               of: object,
                               change: change,
                               context: context)
            return
        }
        if keyPath == #keyPath(AVPlayerItem.status) {
            let status: AVPlayerItemStatus
            
            // Get the status change from the change dictionary
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVPlayerItemStatus(rawValue: statusNumber.intValue)!
            } else {
                status = .unknown
            }
            // Switch over the status
            switch status {
            case .readyToPlay:
                // Player item is ready to play.
                print("Ready to play")
            case .failed:
                // Player item failed. See error.
                print("Player item failed: ", playerItems[currentTrack].error.debugDescription)
            case .unknown:
                // Player item is not yet ready.
                print("Player item not ready")
            }
        }
    }
    
    func previousTrack() {
        if currentTrack == 0 {
            currentTrack = playerItems.count - 1
        } else {
            currentTrack -= 1
        }
        playTrack()
    }
    
    func nextTrack() {
        if currentTrack == playerItems.count - 1 {
            currentTrack = 0
        } else {
            currentTrack += 1;
        }
        playTrack()
    }
    
    func initPlayer() {
        player = AVPlayer.init(playerItem: playerItems[0])
        player?.volume = 1.0
        player?.isMuted = false
        player?.automaticallyWaitsToMinimizeStalling = false
        player?.play()
    }
    
    func playTrack() {
        player?.pause()
        player?.replaceCurrentItem(with: playerItems[currentTrack])
        print("player paused ")
        player?.volume = 1.0
        player?.isMuted = false
        player?.automaticallyWaitsToMinimizeStalling = false
        player?.seek(to: kCMTimeZero)
        player?.play()
        guard let tv:SCNNode = self.sceneView.scene.rootNode.childNode(withName: "tv", recursively: true) else { return }
        print("playing next")
        tv.geometry?.firstMaterial?.diffuse.contents = getSpriteScene(newPlayer: player!)
    }
    
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        if ARWorldTrackingConfiguration.isSupported {
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = .horizontal
            // Run the view's session
            sceneView.session.run(configuration)
            sceneView.isPlaying = true
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
    }
}
