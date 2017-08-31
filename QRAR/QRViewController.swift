//
//  QRViewController.swift
//  QRAR
//
//  Created by Jeff Cedilla on 8/21/17.
//  Copyright © 2017 spaghetticoder. All rights reserved.
//

import UIKit
import SceneKit
import ARKit

class QRViewController: UIViewController {
    
    var detector: CIDetector?
    var userNodes: [ARAnchor: SCNNode] = [:]
    
    private var decodedMessage: String = "No QR" {
        didSet {
            
            for node in mainNode.childNodes {
                node.removeFromParentNode()
            }
            
            if decodedMessage != "No QR" {
                mainNode.addChildNode(makeTextNode(color: .green))
            }
            else {
                mainNode.addChildNode(makeTextNode(color: .red))
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true
        
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    let sceneView: ARSCNView = {
        let sceneView = ARSCNView()
        sceneView.isUserInteractionEnabled = false
        
        sceneView.isOpaque = false
        sceneView.loops = true
        sceneView.backgroundColor = UIColor.white
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.contentMode = .scaleToFill
        sceneView.clipsToBounds = true
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        
        sceneView.scene = SCNScene()
        
        return sceneView
    }()
    
    private lazy var mainNode: SCNNode = {
        let scene = SCNScene()
        let wrapper = SCNNode()
        scene.rootNode.childNodes.forEach { wrapper.addChildNode($0) }
        wrapper.scale = .init(0.25, 0.25, 0.25)
        wrapper.position = .init(0, 0.1, 0)
        wrapper.addChildNode(makeTextNode(color: .green))
        return wrapper
    }()
}

//MARK: - Setup UI

extension QRViewController {

    private func setupViews() {

        sceneView.delegate = self
        
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(self.snapImage(_:)))
        recognizer.numberOfTapsRequired = 1
        sceneView.addGestureRecognizer(recognizer)

        view.addSubview(sceneView)
        
        view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[v0]|", options: NSLayoutFormatOptions(), metrics: nil, views: ["v0": sceneView]))
        
        view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[v0]|", options: NSLayoutFormatOptions(), metrics: nil, views: ["v0": sceneView]))
    }
    
    private func makePlane(from anchor: ARPlaneAnchor) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(anchor.extent.x), height: CGFloat(anchor.extent.z))
        let material = SCNMaterial()
        material.isDoubleSided = true
        material.diffuse.contents = UIColor.green.withAlphaComponent(0.25)
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.position = .init(anchor.center.x, 0, anchor.center.z)
        node.transform = SCNMatrix4MakeRotation(-Float.pi/2, 1, 0, 0)
        node.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: plane, options: [:]))
        return node
    }
    
}

// MARK: - QR Decoding

extension QRViewController {
    
    @objc func snapImage(_ sender: UITapGestureRecognizer) {
        let snapshot = sceneView.snapshot()
        let ciImage = CIImage(image: snapshot)
        decodedMessage = performQRCodeDetection(image: ciImage)
        
        let location = sender.location(in: sceneView)
        let normalizedPoint = CGPoint(x: location.x / sceneView.bounds.size.width,
                                      y: location.y / sceneView.bounds.size.height)
        
        let results = sceneView.session.currentFrame?.hitTest(normalizedPoint, types: [.estimatedHorizontalPlane, .existingPlane, .featurePoint])
        
        guard let closest = results?.first else {
            return
        }
        
        let transform = closest.worldTransform
        let anchor = ARAnchor(transform: transform)
        
        userNodes[anchor] = mainNode
        
        sceneView.session.add(anchor: anchor)
    }
    
    func performQRCodeDetection(image: CIImage?) ->  String {
        
        var decode = "No QR"
        
        let detector: CIDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
        let features = detector.features(in: image!)
        for feature in features as! [CIQRCodeFeature] {
            decode = feature.messageString!
        }
        return decode
    }
    
    private func makeTextNode(color: UIColor) -> SCNNode {
        let scene = SCNScene()
        let textNode = SCNText(string: decodedMessage, extrusionDepth: 0.5)
        textNode.font = UIFont.systemFont(ofSize: 10)
        textNode.flatness = 0
        
        let material = SCNMaterial()
        material.isDoubleSided = true
        material.normal.contents = color
        material.diffuse.contents = color
        material.specular.contents = color
        textNode.materials = [material]
        
        let node = SCNNode(geometry: textNode)
        scene.rootNode.childNodes.forEach { node.addChildNode($0) }
        node.scale = .init(0.05, 0.05, 0.05)
        node.position = .init(-0.5, -0.5, 0)
        node.eulerAngles = .init(0, 0, 0)
        return node
    }
    
    // Unused method for possible future continuous QR Code reading.
    func continuousReading() -> CIImage? {
        guard let image = sceneView.session.currentFrame?.capturedImage else {
            return nil
        }
        
        let ciImage = CIImage(cvPixelBuffer: image)
        
        return ciImage
    }
    
}

// MARK: - AR Delegate Methods
extension QRViewController: ARSCNViewDelegate {
    
    // Anytime an anchor is added to the session, add text node
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            let planeNode = makePlane(from: planeAnchor)
            node.addChildNode(planeNode)
        }
        
        if let userNode = userNodes[anchor] {
            node.addChildNode(userNode)
        }
    }
    
    // Show plane upon successful detection
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            let planeNode = makePlane(from: planeAnchor)
            node.addChildNode(planeNode)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("ERROR: \(error)")
    }
    
    // Disable tapping until ARCamera has finished initializing.
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case ARCamera.TrackingState.normal:
            sceneView.isUserInteractionEnabled = true
        default: break
        }
    }
    
    
    
}

