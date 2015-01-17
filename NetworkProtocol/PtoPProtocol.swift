//
//  PtoPProtocol.swift
//  SkipChat
//
//  Created by Katie Siegel on 1/17/15.
//  Copyright (c) 2015 SkipChat. All rights reserved.
//

import Foundation
import MultipeerConnectivity
//import CommonCrypto

protocol PtoPProtocolDelegate {
    func receive(message : NSData, pubKey : NSData, time : NSDate)
}

public class DataPacket : NSCoding {
    var blob : NSData
    var timeToLive : Int
    
    public init(blob : NSData, ttl : Int) {
        self.blob = blob
        self.timeToLive = ttl
    }
    
    class func deserialize(dataInfo : NSData) -> DataPacket {
        return NSKeyedUnarchiver.unarchiveObjectWithData(dataInfo) as DataPacket
    }
    
    public func serialize() -> NSData {
        return NSKeyedArchiver.archivedDataWithRootObject(self)
    }
    
    public required init(coder aDecoder: NSCoder) {
        self.blob = aDecoder.decodeObjectForKey("blob") as NSData
        self.timeToLive = aDecoder.decodeIntegerForKey("ttl")
    }
    
    public func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeInteger(self.timeToLive, forKey: "ttl")
        aCoder.encodeObject(self.blob, forKey: "blob")
    }
    
    // returns false if dead
    public func decrementTTL() -> Bool {
        return --self.timeToLive > 0
    }
}

public class BufferItem {
    var packetItem : DataPacket
    var receiveTime : NSDate
    
    public init(packet : DataPacket, rTime:NSDate) {
        self.packetItem = packet
        self.receiveTime = rTime
    }

    
//    private func md5: NSData {
//        let str = self.cStringUsingEncoding(NSUTF8StringEncoding)
//        let strLen = CC_LONG(self.lengthOfBytesUsingEncoding(NSUTF8StringEncoding))
//        let digestLen = Int(CC_MD5_DIGEST_LENGTH)
//        let result = UnsafeMutablePointer<CUnsignedChar>.alloc(digestLen)
//        
//        CC_MD5(str!, strLen, result)
//        
//        var hash = NSMutableString()
//        for i in 0..<digestLen {
//            hash.appendFormat("%02x", result[i])
//        }
//        
//        result.dealloc(digestLen)
//        
//        return String(format: hash)
//    }
}

public class PtoPProtocol: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    let serviceType = "pf-connector"
//    var assistant : MCAdvertiserAssistant!
    var advertiser : MCNearbyServiceAdvertiser!
    var session : MCSession!
    var peerID: MCPeerID!
    var browser : MCNearbyServiceBrowser!
    
    var buffer : [BufferItem]
    var privateKey : NSData
    var publicKey : NSData
    var delegate : PtoPProtocolDelegate?
        
    public init(prKey : NSData, pubKey : NSData) {
        self.buffer = []
        self.privateKey = prKey
        self.publicKey = pubKey
        
        self.peerID = MCPeerID(displayName: UIDevice.currentDevice().name)
        
        super.init()
        
        self.session = MCSession(peer: peerID)
        self.session.delegate = self
//        self.assistant = MCAdvertiserAssistant(serviceType:serviceType,
//            discoveryInfo:nil, session:self.session)
//        self.assistant.start() // start advertising
        
        self.advertiser = MCNearbyServiceAdvertiser(peer: self.peerID, discoveryInfo: nil, serviceType: serviceType)
        self.advertiser.delegate = self
        self.advertiser.startAdvertisingPeer()
        
        self.browser = MCNearbyServiceBrowser(peer: self.peerID, serviceType: serviceType)
        self.browser.delegate = self;
        self.browser.startBrowsingForPeers()
        
        println("initialized p2p")
    }
    
    // class methods
    public func send(message: NSData, recipient: NSData){
        var packet = DataPacket(blob: message, ttl: 10) // TODO encrypt
        var item = BufferItem(packet: packet, rTime: NSDate())
        self.buffer.append(item)
    }
    
    public func logPeers() {
        var peers = self.session.connectedPeers
        for peer in peers {
            println("peer ", peer)
        }
        
    }
    
    // MCSessionDelegate
    public func session(session: MCSession!, didReceiveData data: NSData!, fromPeer peerID: MCPeerID!) {
        // Called when a peer sends an NSData to us
        
        // This needs to run on the main queue
        dispatch_async(dispatch_get_main_queue()) {
            
            var msg = NSString(data: data, encoding: NSUTF8StringEncoding)
            
//            self.updateChat(msg, fromPeer: peerID)
        }
    }
    
    public func session(session: MCSession!, didStartReceivingResourceWithName resourceName: String!, fromPeer peerID: MCPeerID!, withProgress progress: NSProgress!) {
        // Called when a peer starts sending a file to us
    }
    
    public func session(session: MCSession!, didFinishReceivingResourceWithName resourceName: String!, fromPeer peerID: MCPeerID!, atURL localURL: NSURL!, withError error: NSError!) {
        // Called when a file has finished transferring from another peer
        println("finished receiving ", resourceName)
    }
    
    
    public func session(session: MCSession!, didReceiveStream stream: NSInputStream!, withName streamName: String!, fromPeer peerID: MCPeerID!) {
        // Called when a peer establishes a stream with us

    }
    
    public func session(session: MCSession!, peer peerID: MCPeerID!, didChangeState state: MCSessionState) {
        // Called when a connected peer changes state (for example, goes offline)
        println("started session with state ", state)
        
        if state == MCSessionState.Connected {
            var error : NSError?
            
            for item in self.buffer {
                self.session.sendData(item.packetItem.serialize(), toPeers: [peerID], withMode: MCSessionSendDataMode.Reliable, error: &error)
                
                if error != nil {
                    print("Error sending data: \(error?.localizedDescription)")
                }
                error = nil
            }
        }
        self.logPeers()
    }
    
    // MCNearbyServiceAdvertiserDelegate
    
    public func advertiser(advertiser: MCNearbyServiceAdvertiser!, didNotStartAdvertisingPeer error: NSError!) {
        println("Advertiser " + self.peerID.displayName + " did not start advertising with error: " + error.localizedDescription);
    }
    
    public func advertiser(advertiser: MCNearbyServiceAdvertiser!, didReceiveInvitationFromPeer peerID: MCPeerID!, withContext context: NSData!, invitationHandler: ((Bool, MCSession!) -> Void)!) {
        println("Advertiser " + self.peerID.displayName + " received an invitation from " + peerID.displayName)
        invitationHandler(true, self.session);
        println("Advertiser " + self.peerID.displayName + " accepted invitation from " + peerID.displayName)
    }
    
    // MCNearbyServiceBrowser
    
    public func browser(browser: MCNearbyServiceBrowser!, didNotStartBrowsingForPeers error: NSError!) {
        println("Browser " + self.peerID.displayName + " did not start browsing with error: " + error.localizedDescription)
    }
    
    public func browser(browser: MCNearbyServiceBrowser!, foundPeer peerID: MCPeerID!, withDiscoveryInfo info: [NSObject : AnyObject]!) {
        self.browser.invitePeer(peerID, toSession: self.session, withContext: nil, timeout: 30) // what is this constant TODO]
        println("found peer %@", peerID)
        
    }
    
    public func browser(browser: MCNearbyServiceBrowser!, lostPeer peerID: MCPeerID!) {
        self.logPeers()
        println("lost peer %@", peerID)
    }
    
}