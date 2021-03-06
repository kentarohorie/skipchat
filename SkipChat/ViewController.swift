//
//  ViewController.swift
//  SkipChat
//
//  Created by Katie Siegel on 1/17/15.
//  Copyright (c) 2015 SkipChat. All rights reserved.
//

import UIKit
import CoreData
import AddressBookUI
import AddressBook

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, PtoPProtocolDelegate, UINavigationBarDelegate, LGChatControllerDelegate {
    let IOS_BAR_HEIGHT : Float = 20.0
    let ROWS_PER_SCREEN : Float = 8.0
    let NAV_BAR_HEIGHT : Float = 64.0
    var networkingLayer : PtoPProtocol!
    var messageTable = UITableView(frame: CGRectZero, style: .Plain)
    var navBar : UINavigationBar = UINavigationBar(frame: CGRectZero)
    var messages : NSMutableDictionary = NSMutableDictionary()
    var contacts : NSMutableArray = NSMutableArray()
    let contaggedManager : ContaggedManager = ContaggedManager();
    var currentChatPubKey : String?
    var chatController : LGChatController = LGChatController()
    var chatControllerSet : Bool = false

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    lazy var managedObjectContext : NSManagedObjectContext? = {
        let appDelegate = UIApplication.sharedApplication().delegate as AppDelegate
        if let managedObjectContext = appDelegate.managedObjectContext {
            return managedObjectContext
        }
        else {
            return nil
        }
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        if(ContaggedManager.getAuthorizationStatus() != ABAuthorizationStatus.Authorized){
            
            swiftAddressBook?.requestAccessWithCompletion({ (success, error) -> Void in
                if success {
                    //do something with swiftAddressBook
                } else {
                    //no success, access denied. Optionally evaluate error
                }
            })
        }
        
        // Do any additional setup after loading the view, typically from a nib.
        self.networkingLayer = PtoPProtocol.sharedInstance
        self.networkingLayer.delegate = self
        
        fetchMessages()
        
        // Store the full frame in a temporary variable
        var viewFrame = self.view.frame
        
        // Adjust it down by 20 points
        viewFrame.origin.y += CGFloat(NAV_BAR_HEIGHT)
        
        // Reduce the total height by 20 points
        viewFrame.size.height -= CGFloat(NAV_BAR_HEIGHT)
        
        // Set the logTableview's frame to equal our temporary variable with the full size of the view
        // adjusted to account for the status bar height
        self.messageTable.frame = viewFrame
        
        // Add the table view to this view controller's view
        self.view.addSubview(messageTable)
        
        // Here, we tell the table view that we intend to use a cell we're going to call "LogCell"
        // This will be associated with the standard UITableViewCell class for now
        self.messageTable.registerClass(MessageTableViewCell.classForCoder(), forCellReuseIdentifier: "MessageCell")
        
        // This tells the table view that it should get it's data from this class, ViewController
        self.messageTable.dataSource = self
        self.messageTable.delegate = self
        
        
        navBar.frame = CGRectMake(0, 0, self.view.frame.width, CGFloat(NAV_BAR_HEIGHT))
        navBar.layer.masksToBounds = false
        navBar.delegate = self
        
        // Create a navigation item with a title
        let navigationItem = UINavigationItem()
        navigationItem.title = "SkipChat"
        
        // Create left and right button for navigation item
        //        let leftButton = UIBarButtonItem(title: "Edit", style: UIBarButtonItemStyle.Plain, target: self, action: nil)
        let rightButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.Compose, target: self, action: "composeNewMessage")
        
        // Create two buttons for the navigation item
        //        navigationItem.leftBarButtonItem = leftButton
        navigationItem.rightBarButtonItem = rightButton
        
        // Assign the navigation item to the navigation bar
        navBar.items = [navigationItem]
        
        
        self.view.addSubview(navBar)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func fetchMessages() {
        let fetchRequest = NSFetchRequest(entityName: "Message")
        
        // Create a sort descriptor object that sorts on the "title"
        // property of the Core Data object
        let sortDescriptor = NSSortDescriptor(key: "contactDate", ascending: true)
        
        // Set the list of sort descriptors in the fetch request,
        // so it includes the sort descriptor
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        messages = NSMutableDictionary()
        contacts = NSMutableArray()
        if let fetchResults = managedObjectContext!.executeFetchRequest(fetchRequest, error: nil) as? [Message] {
            var allMessages = fetchResults
            for message in allMessages {
                println(message.publicKey + " " + message.text)
                var personMessages = NSMutableArray()
                if (messages.objectForKey(message.publicKey) != nil) {
                    personMessages = messages.objectForKey(message.publicKey) as NSMutableArray
                } else {
                    self.contacts.insertObject(message.publicKey, atIndex: 0)
                }
                personMessages.addObject(message)
                messages.setObject(personMessages, forKey: message.publicKey)
            }
        }
        
        self.messageTable.reloadData()
    }

    // UITableViewDataSource
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("MessageCell") as MessageTableViewCell
        
        // Get the message for this index
        let messageItems = messages[contacts[indexPath.row] as String] as [Message]
        let messageItem = messageItems[messageItems.count-1]
        
        // Set the title of the cell to be the title of the logItem
        cell.messagePeerLabel.text = messageItem.peer
        cell.messageTextLabel.text = messageItem.text
        
        return cell
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contacts.count;
    }
    
    // UITableViewDelegate
    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return 80
    }
    
    func getMessagesForPublicKey(publicKey : String) -> [LGChatMessage] {
        if ((self.messages.objectForKey(publicKey)) != nil) {
            var userMessages = self.messages[publicKey] as [Message]
            return makeLGMessages(userMessages)
        }
        return []

    }
    
    func getEarliestMessageForPublicKey(publicKey : String) -> Message {
        return (self.messages[publicKey] as [Message])[0]
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        println("pushing new controller")
        chatController = LGChatController()
//        chatController.opponentImage = UIImage(named: "User")
        chatController.messages = getMessagesForPublicKey(contacts[indexPath.row] as String) as [LGChatMessage]
        let earliestMessage = getEarliestMessageForPublicKey(contacts[indexPath.row] as String) as Message
        chatController.peer = earliestMessage.peer
        chatController.peerPublicKey = earliestMessage.publicKey
        currentChatPubKey = earliestMessage.publicKey
        chatController.rootView = self
        chatController.delegate = self
        chatControllerSet = true
        self.messageTable.deselectRowAtIndexPath(indexPath, animated: true)
        self.presentViewController(chatController, animated: true, completion: nil)
    }
    
    internal func composeNewMessage() {
        chatController = LGChatController()
//        chatController.opponentImage = UIImage(named: "User")
        chatController.delegate = self
        chatController.isNewMessage = true
        chatController.rootView = self
//        chatController.peer = "Name"
        chatControllerSet = true
//        chatController.peerPublicKey = "LS0tLS1CRUdJTiBSU0EgUFVCTElDIEtFWS0tLS0tCk1JSUNDZ0tDQWdFQXF0OTVtTnJla29IUXhPYkpwYnZ5a29TZjJOcUpqcU9HdWNOcWtGQXNUS2NBdGpyd2FHbUEKY1k2Z2thaWRYK3I1Zk1LcVU4azRxNERCQ1Q5TVVhelFBMi82eWVxKzVyTVVKYnhLdkdXU1AwckthRno2dWVNKwpUdkZkcVF6THFmTzVEKzhBTVlrZUYzV210ZFA1dnJ5UjMyZDFUTDFYdjIxaGZxWEROVEZ2UVBJR1ErMXNyNFcvCloyL1YycFN6U053OFJKN3lYNUlxTStqWmVWTVMvL3RmanJUSkZqTmhsVi9FZXI1TnhjOHB5MEhPZllKRXFvTjAKUGZ0V3Q0TzlTSEtsZkI4UE5mSEZPYkV0Z1A0ejJ2YmhERmNwTExYeEVKeHFOWXRjaG8rSmZoaEpJeGFmUXlQeQp1NFl5WVBhdWFBM0VLRzJOS1VpNXhRaDIzamRLOGo1Z3oreVpOL05BTWpPZ1lNQ3pwSEJWaXNRTWlrQlFuSEVlCjV1bllpVHpxVUJSVnlRaUJ6YlFaMWdEdkxtZmNsOStoSElhdXlvelgzSEpNTlpYa3dlNVlzTlhhNDdrOVRwQmgKZE9PaU93MHpVdTlTZFhqWGx0dlpZSFdSUjR2SFZUbGpkZDZLWm5YZjE0NDhWeWl2MnRIMVEvRitSb2NBa0VnRgp0Z2tOc21QQ3NXSXVIU2ZvYytLOTRNYnZCR2FPbTRPUTFlM21kV09EWDdDbHpEcXZaOG5kODdielEzMnlCcUFSCi85ZHFjdGJmd2R6dnlNZUhZWHNmQUsyRGJHZjNVV1NMc0FoK0pwQ1Ird0FmcStPQWdNc2xKNWdMMUpZSUR1bCsKTXIwTWgvRkFWZVR5eG1vb29yYURHUnMxVU80V3VJdjBEcGpUdmg0aGd2aWRscVNGRTZ5clBOa0NBd0VBQVE9PQotLS0tLUVORCBSU0EgUFVCTElDIEtFWS0tLS0tCgA="
        self.presentViewController(chatController, animated: true, completion: nil)
    }

    func makeLGMessages(userMessages : [Message]) -> [LGChatMessage] {
        var lgMessages : [LGChatMessage] = []
        for message in userMessages {
            var sender = LGChatMessage.SentBy.User
            if message.outgoing == false {
                sender = LGChatMessage.SentBy.Opponent
            }
            lgMessages.append(LGChatMessage(content: message.text, sentBy: sender))
        }
        return lgMessages
    }
    
    // LGChatControllerDelegate
    func chatController(chatController: LGChatController, didAddNewMessage message: LGChatMessage) {
        println("Did Add Message: \(message.content)")
    }
    
    func shouldChatController(chatController: LGChatController, addMessage message: LGChatMessage) -> Bool {
        /*
        Use this space to prevent sending a message, or to alter a message.  For example, you might want to hold a message until its successfully uploaded to a server.
        */
        return true
    }
    
    // PtPProtocolDelegate
    func receive(message : NSData, pubKey : NSData, time : NSDate) {
        println("received message on frontend")
        
        var messageText = NSString(data: message, encoding: NSUTF8StringEncoding)!
        var messagePublicKey = NSString(data: pubKey, encoding: NSUTF8StringEncoding)!
        var messagesForPubKey : [Message] = []
        if (self.contacts.containsObject(messagePublicKey)) {
            messagesForPubKey = self.messages[messagePublicKey] as [Message]
        }
        for message in messagesForPubKey {
            let sameTime = message.contactDate.compare(time) == NSComparisonResult.OrderedSame
            let sameMsg = messageText.isEqualToString(message.text)
            if sameMsg && sameTime {
                println("skipping duplicate message")
                return
            }
        }
        if let moc = self.managedObjectContext {
            Message.createInManagedObjectContext(moc,
                peer: contaggedManager.getPeerName("pubkey", value: messagePublicKey), //TODO
                publicKey: messagePublicKey,
                text: messageText,
                outgoing: false,
                contactDate: time
            )
        }
        var error : NSError? = nil
        if !self.managedObjectContext!.save(&error) {
            NSLog("Unresolved error \(error), \(error!.userInfo)")
            abort()
        }
        self.fetchMessages()
        println("starting")
        println(messagePublicKey)
        var notOptionalKey : String = ""
        if (self.chatController.peerPublicKey != nil) {
            notOptionalKey = self.chatController.peerPublicKey!
        }
        println(notOptionalKey)
//        if notOptionalKey != "" && pubKey == notOptionalKey { //TODO(katie) shame on you
        if chatControllerSet {
            self.chatController.addNewMessage(LGChatMessage(content: messageText, sentBy: LGChatMessage.SentBy.Opponent))
        }
    }
}

