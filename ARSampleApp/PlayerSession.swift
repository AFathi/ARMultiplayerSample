//
//  PlayerSession.swift
//
//  Created by Ahmed Bekhit on 8/17/18.
//  Copyright © 2018 Ahmed Fathi Bekhit. All rights reserved.
//

import MultipeerConnectivity

/// An enum that denotes the player's session status
enum PlayerStatus {
    case connected
    case connecting
    case available
    case lost
}

/// A simple struct object that stores a player's id, name, and status.
struct Player: Equatable, Hashable {
    var id: MCPeerID
    var name: String
    var status: PlayerStatus?
    static func == (lhs: Player, rhs: Player) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name
    }
}

/// A class built to simplify the process of using MultipeerConnectivity in AR shared experiences.
class PlayerSession: NSObject {
    fileprivate let userPeerID = MCPeerID(displayName: UIDevice.current.name)
    fileprivate var session: MCSession!
    fileprivate var serviceAdvertiser: MCNearbyServiceAdvertiser!
    fileprivate var serviceBrowser: MCNearbyServiceBrowser!
    
    fileprivate var receivedDataFromPlayer: (Data, Player) -> Swift.Void = { _, _ in }
    fileprivate var receivedInviteFromPlayer: (Player) -> Swift.Void = {_ in}
    fileprivate var sendInviteResponseToPlayer: () throws -> Bool? = { return nil }
    fileprivate var updateNearbyPlayers: (Player) -> Swift.Void = { _ in }
    fileprivate var connectedToPlayer: (Player) -> Swift.Void = { _ in }
    
    fileprivate var playersPermissions: [MCPeerID: Bool] = [:]
    
    /// An instance that will be used to find nearby players using your app or game. NOTE:- make sure the name is less than 15 characters. More info on serviceType naming can be found [here](https://developer.apple.com/documentation/multipeerconnectivity/mcnearbyserviceadvertiser/1407102-initwithpeer)
    public var appMCName = "ar-app-sample" {
        didSet{
            serviceAdvertiser.stopAdvertisingPeer()
            serviceBrowser.stopBrowsingForPeers()
            
            serviceAdvertiser = MCNearbyServiceAdvertiser(peer: userPeerID, discoveryInfo: nil, serviceType: self.appMCName)
            serviceAdvertiser.delegate = self
            serviceAdvertiser.startAdvertisingPeer()
            
            serviceBrowser = MCNearbyServiceBrowser(peer: userPeerID, serviceType: self.appMCName)
            serviceBrowser.delegate = self
            serviceBrowser.startBrowsingForPeers()
        }
    }
    
    /// An instance that returns the nearby players in an array
    public fileprivate(set) var nearbyPlayers: [Player] = []
    
    /// An instance that returns the connected players in an array
    public var connectedPlayers: [Player] {
        let approvedPlayers = session.connectedPeers.filter { peer in
            return playersPermissions[peer] == true
        }
        let players = approvedPlayers.map { peer in
            return Player(id: peer, name: peer.displayName, status: .connected)
        }
        return players
    }
    
    /// Singleton
    public static let shared = PlayerSession()
    
    /// Initializes the Multipeer Connectivity instances and automatically begins to search for nearby players
    public override init() {
        super.init()
        
        session = MCSession(peer: userPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        serviceAdvertiser = MCNearbyServiceAdvertiser(peer: userPeerID, discoveryInfo: nil, serviceType: self.appMCName)
        serviceAdvertiser.delegate = self
        serviceAdvertiser.startAdvertisingPeer()
        
        serviceBrowser = MCNearbyServiceBrowser(peer: userPeerID, serviceType: self.appMCName)
        serviceBrowser.delegate = self
        serviceBrowser.startBrowsingForPeers()
    }
    
    /// This function notifies you when the user receives an invitation from another player.
    public func didReceiveInvitation(_ invitation: @escaping (Player) -> Swift.Void) {
        self.receivedInviteFromPlayer = invitation
    }
    
    /// This function allows you to respond to a player's invitation using a boolean.
    public func respondToInvitation(from player: Player, with response: Bool) {
        let userResponse = (response) ? "accepted invitation" : "denied invitation"
        let dict = [userResponse: userPeerID]
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: false) else { print("An error occurred while archiving the invitation"); return}
        self.sendData(data, to: [player.id])
        
    }
    
    /// This function notifies you whether a player is available to join or not.
    public func didUpdateNearbyPlayers(_ p: @escaping (Player) -> Swift.Void) {
        self.updateNearbyPlayers = p
    }
    
    /// This function notifies you when the player receives data from another player.
    public func didReceiveData(_ dataFromPlayer: @escaping (Data, Player) -> Swift.Void) {
        self.receivedDataFromPlayer = dataFromPlayer
    }
    
    /// This function allows you to connect to a player and returns the player's status, i.e. connected or not connected.
    public func connectToPlayer(_ player: Player, _ finished: @escaping (Player) -> Swift.Void) {
        self.connectedToPlayer = finished
        serviceBrowser.invitePeer(player.id, to: session, withContext: nil, timeout: 10)
    }
    
    /// This function allows you to send data to all connected users.
    public func sendData(_ data: Data, to players: [MCPeerID]? = nil) {
        let approvedPlayers = session.connectedPeers.filter { peer in
            return playersPermissions[peer] == true
        }
        
        let peers = (players == nil) ? approvedPlayers : players
        
        do {
            try session.send(data, toPeers: peers!, with: .reliable)
        } catch {
            print("An error occurred while sending data to players: \(error.localizedDescription)")
        }
    }
    
}

extension PlayerSession: MCSessionDelegate {
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let unarchived = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data), let response = unarchived as? [String: MCPeerID] {
            if let invitedPlayer = response["accepted invitation"] {
                let player = Player(id: invitedPlayer, name: invitedPlayer.displayName, status: .connected)
                // Updating the connection status of a specific player when player accepted
                playersPermissions.updateValue(true, forKey: invitedPlayer)
                connectedToPlayer(player)
            }else if let invitedPlayer = response["denied invitation"] {
                let player = Player(id: invitedPlayer, name: invitedPlayer.displayName, status: .available)
                // Updating the connection status of a specific player when player denied
                playersPermissions.updateValue(false, forKey: invitedPlayer)
                connectedToPlayer(player)
            }
        }else{
            let player = Player(id: peerID, name: peerID.displayName, status: .connected)
            receivedDataFromPlayer(data, player)
        }
    }
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let status: PlayerStatus
        switch state {
        case .notConnected:
            status = .available
        case .connecting:
            status = .connecting
        case .connected:
            return
        }
        
        let newPlayer = Player(id: peerID, name: peerID.displayName, status: status)
        
        // Updating the connection status of a specific player
        connectedToPlayer(newPlayer)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // May be used instead of `didReceive data` if you'd want to send big chunks of data. In this case, it would be in an `InputStream` format.
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
    }
}

extension PlayerSession: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let newPlayer = Player(id: peerID, name: peerID.displayName, status: .available)
        
        let hasPlayerId = nearbyPlayers.contains { player in
            return player == newPlayer
        }
        
        if !hasPlayerId {
            playersPermissions.updateValue(false, forKey: peerID)
            
            // Adding nearby player if not already available
            nearbyPlayers.append(newPlayer)
            
            // Notifying that the `nearbyPlayers` array has been updated
            updateNearbyPlayers(newPlayer)
        }
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let lostPlayer = Player(id: peerID, name: peerID.displayName, status: .lost)
        // Removing lost player
        nearbyPlayers.removeAll { player in
            return player == lostPlayer
        }
        
        // Notifying that the `nearbyPlayers` array has been updated
        updateNearbyPlayers(lostPlayer)
    }
    
}

extension PlayerSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let requestedPlayer = Player(id: peerID, name: peerID.displayName, status: .available)
        
        // Updating the connection status of a specific player when player send invitation
        playersPermissions.updateValue(true, forKey: peerID)
        
        // Notifying that the player has received an invitation
        receivedInviteFromPlayer(requestedPlayer)
        
        invitationHandler(true, self.session)
    }
}
