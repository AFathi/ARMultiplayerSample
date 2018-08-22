//
//  ViewController.swift
//  ARSampleApp
//
//  Created by Ahmed Bekhit on 8/19/18.
//  Copyright © 2018 Ahmed Bekhit. All rights reserved.
//

import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {

    @IBOutlet var sceneView: ARSCNView!
    
    // Nearby users IB instances
    @IBOutlet weak var nearbyUsersView: UITableView!
    @IBOutlet weak var inviteBtn: UIButton!
    @IBOutlet weak var nearbyViewTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var stateTextView: UITextView!
    
    // Stores the selected players from the table view.
    var selectedPlayers:[Player] = []
    
    // A variable that determines whether a user initiated the session or not.
    var isMainUser = false
    
    // A variable that stores more recent map update time
    var recentTime = Date().timeIntervalSince1970
    
    // Creates an instance of the PlayerSession class
    let session = PlayerSession.shared
    
    
    // Returns a 3D character from assets
    var maxCharacter: SCNNode {
        let sceneURL = Bundle.main.url(forResource: "max", withExtension: "scn", subdirectory: "Character.scnassets")!
        let refNode = SCNReferenceNode(url: sceneURL)!
        refNode.load()
        return refNode
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sceneView.delegate = self
        
        session.didUpdateNearbyPlayers { _ in
            if self.session.nearbyPlayers.count == 0 {
                self.selectedPlayers.removeAll()
            }
            self.nearbyUsersView.reloadData()
        }
        
        session.didReceiveInvitation { player in
            let requestAlert = UIAlertController(title: "Join Game Request", message: "Would you like to join \(player.name) game?", preferredStyle: .alert)
            requestAlert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { _ in
                // allow sending/receiving from/to that player
                self.session.respondToInvitation(from: player, with: true)
                self.nearbyViewTopConstraint.constant = 570
                self.stateTextView.text = "Total number of players in this session including you: (\(self.session.connectedPlayers.count+1)). Players in this session are: \n"
                for player in self.session.connectedPlayers {
                    self.stateTextView.text.append("\n- \(player.name)")
                }
            }))
            
            requestAlert.addAction(UIAlertAction(title: "No", style: .cancel, handler: { _ in
                // block sending/receiving from/to that player
                self.session.respondToInvitation(from: player, with: false)
            }))
            self.present(requestAlert, animated: true)
        }
        
        session.didReceiveData { data, player in
            if let unarchived = try? NSKeyedUnarchiver.unarchivedObject(of: ARWorldMap.classForKeyedUnarchiver(), from: data),
                let worldMap = unarchived as? ARWorldMap {
                
                // Run the session with the received world map.
                let configuration = ARWorldTrackingConfiguration()
                configuration.planeDetection = .horizontal
                configuration.initialWorldMap = worldMap
                self.sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
                
            }else if let unarchived = try? NSKeyedUnarchiver.unarchivedObject(of: ARAnchor.classForKeyedUnarchiver(), from: data), let anchor = unarchived as? ARAnchor {
                    self.sceneView.session.add(anchor: anchor)
            }else{
                print("unknown data recieved from \(player)")
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        guard ARWorldTrackingConfiguration.isSupported else {
            let errorAlert = UIAlertController(title: "ARKit Error", message: "This device doesn't support ARKit.", preferredStyle: .alert)
            errorAlert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: {_ in}))
            self.present(errorAlert, animated: true)
            return
        }
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        
        // Run the view's session
        sceneView.session.run(configuration)
        
        sceneView.session.delegate = self
        // enabling debugging feature points
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]

        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ok", style: .cancel, handler: {_ in}))
        self.present(alert, animated: true)
    }
    
    // Send invitation to selected players
    @IBAction func invitePlayers(_ sender: UIButton) {
        SwiftSpinner.show("Sending requests to join...")
        // Iterating thru the `selectedPlayers` array and invited all selected players.
        for (i, player) in selectedPlayers.enumerated() {
            self.session.connectToPlayer(player) { player in
                // Checking whether that's the last player from the `selectedPlayers` array
                if i == self.selectedPlayers.count-1 {
                    // If last player accepted invitation do the following
                    if player.status == .connected {
                        // Hide loading indicator, inform user they've been connected, and finally update the `stateTextView`
                        SwiftSpinner.hide()
                        self.isMainUser = true
                        self.nearbyViewTopConstraint.constant = 570
                        self.showAlert(title: "Successfully Connected", message: "You have been successfully connected. Click \"ok\" to begin sharing your AR experience.")
                        self.stateTextView.text = "Total number of players in this session including you: (\(self.session.connectedPlayers.count+1)). Players in this session are: \n"
                        for player in self.session.connectedPlayers {
                            self.stateTextView.text.append("\n- \(player.name)")
                        }
                    }else if player.status == .connecting {
                        // Updating loading indicator to "Waiting on players to respond..."
                        DispatchQueue.main.async {
                            SwiftSpinner.show("Waiting on players to respond...")
                        }
                    }else{
                        SwiftSpinner.hide()
                        if self.session.connectedPlayers.count > 0 {
                            self.isMainUser = true
                            self.nearbyViewTopConstraint.constant = 570
                            self.showAlert(title: "Successfully Connected", message: "You have been successfully connected. Click \"ok\" to begin sharing your AR experience.")
                            self.stateTextView.text = "Total number of players in this session including you: (\(self.session.connectedPlayers.count+1)). Players in this session are: \n"
                            for player in self.session.connectedPlayers {
                                self.stateTextView.text.append("\n- \(player.name)")
                            }
                        }else{
                            self.showAlert(title: "Failed to Connect", message: "An error occurred while connecting. Please try again.")
                        }
                    }
                }
            }
        }
    }
    
    @IBAction func didTapOnView(_ sender: UITapGestureRecognizer) {
        // Hit test to find a place for a virtual object.
        guard let hitTestResult = sceneView
            .hitTest(sender.location(in: sceneView), types: [.existingPlaneUsingGeometry, .estimatedHorizontalPlane])
            .first
            else { return }
        
        // Place an anchor for a virtual character. The model appears in renderer(_:didAdd:for:).
        let anchor = ARAnchor(name: "maxAR", transform: hitTestResult.worldTransform)
        sceneView.session.add(anchor: anchor)
        
        // Send the anchor info to players
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else {
            print("an error occurred while encoding the anchor")
            return
        }
        
        self.session.sendData(data)
    }
    
    // MARK: - ARSCNViewDelegate
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let name = anchor.name, name.hasPrefix("maxAR") {
            node.addChildNode(maxCharacter)
        }
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        switch frame.worldMappingStatus {
        case .notAvailable:
            break
        case .limited, .extending, .mapped:
            // Sends map data when there are connected players every 40 seconds
            if self.session.connectedPlayers.count > 0 && self.isMainUser && Date().timeIntervalSince1970-self.recentTime > 40 {
                self.recentTime = Date().timeIntervalSince1970
                sceneView.session.getCurrentWorldMap { worldMap, error in
                    guard let map = worldMap else {
                        print("Error: \(error!.localizedDescription)")
                        return
                    }
                    guard let data = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true) else {
                        print("an error occurred while encoding the map")
                        return
                    }
                    self.session.sendData(data)
                }
            }
        }
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

// MARK:- UITableViewDelegate
extension ViewController: UITableViewDelegate, UITableViewDataSource {
    
    // Returns the total number of nearby players using `ARSampleApp` into a table view.
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return session.nearbyPlayers.count
    }
    
    // Listing the nearby players in table view cells
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = nearbyUsersView.dequeueReusableCell(withIdentifier: "nearbyUser", for: indexPath)
        cell.textLabel?.text = session.nearbyPlayers[indexPath.row].name
        cell.detailTextLabel?.text = "Tap to select"

        return cell
    }
    
    // Storing player selection data into `selectedPlayers` array to use it later when sending invitations.
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        nearbyUsersView.deselectRow(at: indexPath, animated: true)
        let cell = nearbyUsersView.cellForRow(at: indexPath)

        let currentPlayer = session.nearbyPlayers[indexPath.row]
        let isSelected = selectedPlayers.contains(where: { player in
            return player == currentPlayer
        })
        
        if isSelected {
            cell?.textLabel?.textColor = .white
            cell?.detailTextLabel?.text = "Tap to select"
            selectedPlayers.removeAll { player in
                return player == currentPlayer
            }
        }else{
            cell?.textLabel?.textColor = .cyan
            cell?.detailTextLabel?.text = "Tap to deselect"
            selectedPlayers.append(currentPlayer)
        }
        
        if selectedPlayers.count > 0 {
            self.inviteBtn.isEnabled = true
        }else{
            self.inviteBtn.isEnabled = false
        }
    }
}
