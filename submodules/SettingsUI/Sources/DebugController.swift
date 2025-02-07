import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import SyncCore
import MtProtoKit
import MessageUI
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import OverlayStatusController
import AccountContext
import TelegramCallsUI

@objc private final class DebugControllerMailComposeDelegate: NSObject, MFMailComposeViewControllerDelegate {
    public func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil)
    }
}

private final class DebugControllerArguments {
    let sharedContext: SharedAccountContext
    let context: AccountContext?
    let mailComposeDelegate: DebugControllerMailComposeDelegate
    let presentController: (ViewController, ViewControllerPresentationArguments?) -> Void
    let pushController: (ViewController) -> Void
    let getRootController: () -> UIViewController?
    
    init(sharedContext: SharedAccountContext, context: AccountContext?, mailComposeDelegate: DebugControllerMailComposeDelegate, presentController: @escaping (ViewController, ViewControllerPresentationArguments?) -> Void, pushController: @escaping (ViewController) -> Void, getRootController: @escaping () -> UIViewController?) {
        self.sharedContext = sharedContext
        self.context = context
        self.mailComposeDelegate = mailComposeDelegate
        self.presentController = presentController
        self.pushController = pushController
        self.getRootController = getRootController
    }
}

private enum DebugControllerSection: Int32 {
    case logs
    case logging
    case experiments
    case videoExperiments
    case videoExperiments2
    case info
}

private enum DebugControllerEntry: ItemListNodeEntry {
    case sendLogs(PresentationTheme)
    case sendOneLog(PresentationTheme)
    case sendShareLogs
    case sendNotificationLogs(PresentationTheme)
    case sendCriticalLogs(PresentationTheme)
    case accounts(PresentationTheme)
    case logToFile(PresentationTheme, Bool)
    case logToConsole(PresentationTheme, Bool)
    case redactSensitiveData(PresentationTheme, Bool)
    case enableRaiseToSpeak(PresentationTheme, Bool)
    case keepChatNavigationStack(PresentationTheme, Bool)
    case skipReadHistory(PresentationTheme, Bool)
    case crashOnSlowQueries(PresentationTheme, Bool)
    case clearTips(PresentationTheme)
    case reimport(PresentationTheme)
    case resetData(PresentationTheme)
    case resetDatabase(PresentationTheme)
    case resetDatabaseAndCache(PresentationTheme)
    case resetHoles(PresentationTheme)
    case reindexUnread(PresentationTheme)
    case resetBiometricsData(PresentationTheme)
    case optimizeDatabase(PresentationTheme)
    case photoPreview(PresentationTheme, Bool)
    case knockoutWallpaper(PresentationTheme, Bool)
    case demoVideoChats(Bool)
    case playerEmbedding(Bool)
    case playlistPlayback(Bool)
    case voiceConference
    case preferredVideoCodec(Int, String, String?, Bool)
    case disableVideoAspectScaling(Bool)
    case enableVoipTcp(Bool)
    case hostInfo(PresentationTheme, String)
    case versionInfo(PresentationTheme)
    
    var section: ItemListSectionId {
        switch self {
        case .sendLogs, .sendOneLog, .sendShareLogs, .sendNotificationLogs, .sendCriticalLogs:
            return DebugControllerSection.logs.rawValue
        case .accounts:
            return DebugControllerSection.logs.rawValue
        case .logToFile, .logToConsole, .redactSensitiveData:
            return DebugControllerSection.logging.rawValue
        case .enableRaiseToSpeak, .keepChatNavigationStack, .skipReadHistory, .crashOnSlowQueries:
            return DebugControllerSection.experiments.rawValue
        case .clearTips, .reimport, .resetData, .resetDatabase, .resetDatabaseAndCache, .resetHoles, .reindexUnread, .resetBiometricsData, .optimizeDatabase, .photoPreview, .knockoutWallpaper, .demoVideoChats, .playerEmbedding, .playlistPlayback, .voiceConference:
            return DebugControllerSection.experiments.rawValue
        case .preferredVideoCodec:
            return DebugControllerSection.videoExperiments.rawValue
        case .disableVideoAspectScaling, .enableVoipTcp:
            return DebugControllerSection.videoExperiments2.rawValue
        case .hostInfo, .versionInfo:
            return DebugControllerSection.info.rawValue
        }
    }
    
    var stableId: Int {
        switch self {
        case .sendLogs:
            return 0
        case .sendOneLog:
            return 1
        case .sendShareLogs:
            return 2
        case .sendNotificationLogs:
            return 3
        case .sendCriticalLogs:
            return 4
        case .accounts:
            return 5
        case .logToFile:
            return 6
        case .logToConsole:
            return 7
        case .redactSensitiveData:
            return 8
        case .enableRaiseToSpeak:
            return 9
        case .keepChatNavigationStack:
            return 10
        case .skipReadHistory:
            return 11
        case .crashOnSlowQueries:
            return 12
        case .clearTips:
            return 13
        case .reimport:
            return 14
        case .resetData:
            return 15
        case .resetDatabase:
            return 16
        case .resetDatabaseAndCache:
            return 17
        case .resetHoles:
            return 18
        case .reindexUnread:
            return 19
        case .resetBiometricsData:
            return 20
        case .optimizeDatabase:
            return 21
        case .photoPreview:
            return 22
        case .knockoutWallpaper:
            return 23
        case .demoVideoChats:
            return 24
        case .playerEmbedding:
            return 26
        case .playlistPlayback:
            return 27
        case .voiceConference:
            return 28
        case let .preferredVideoCodec(index, _, _, _):
            return 29 + index
        case .disableVideoAspectScaling:
            return 100
        case .enableVoipTcp:
            return 101
        case .hostInfo:
            return 102
        case .versionInfo:
            return 103
        }
    }
    
    static func <(lhs: DebugControllerEntry, rhs: DebugControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DebugControllerArguments
        switch self {
        case let .sendLogs(theme):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Send Logs (Up to 40 MB)", label: "", sectionId: self.section, style: .blocks, action: {
                let _ = (Logger.shared.collectLogs()
                |> deliverOnMainQueue).start(next: { logs in
                    let presentationData = arguments.sharedContext.currentPresentationData.with { $0 }
                    let actionSheet = ActionSheetController(presentationData: presentationData)
                    
                    var items: [ActionSheetButtonItem] = []
                    
                    if let context = arguments.context {
                        items.append(ActionSheetButtonItem(title: "Via Telegram", color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            
                            let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyWriteable, .excludeDisabled]))
                            controller.peerSelected = { [weak controller] peer in
                                let peerId = peer.id
                                
                                if let strongController = controller {
                                    strongController.dismiss()
                                    
                                    let lineFeed = "\n".data(using: .utf8)!
                                    var logData: Data = Data()
                                    for (name, path) in logs {
                                        if !logData.isEmpty {
                                            logData.append(lineFeed)
                                            logData.append(lineFeed)
                                        }
                                        
                                        logData.append("------ File: \(name) ------\n".data(using: .utf8)!)
                                        
                                        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                                            logData.append(data)
                                        }
                                    }
                                    
                                    let id = arc4random64()
                                    let fileResource = LocalFileMediaResource(fileId: id, size: logData.count, isSecretRelated: false)
                                    context.account.postbox.mediaBox.storeResourceData(fileResource.id, data: logData)
                                    
                                    let file = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: fileResource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/text", size: logData.count, attributes: [.FileName(fileName: "Log-iOS-Full.txt")])
                                    let message: EnqueueMessage = .message(text: "", attributes: [], mediaReference: .standalone(media: file), replyToMessageId: nil, localGroupingKey: nil)
                                    
                                    let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [message]).start()
                                }
                            }
                            arguments.pushController(controller)
                        }))
                    }
                    items.append(ActionSheetButtonItem(title: "Via Email", color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        
                        let composeController = MFMailComposeViewController()
                        composeController.mailComposeDelegate = arguments.mailComposeDelegate
                        composeController.setSubject("Telegram Logs")
                        for (name, path) in logs {
                            if let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) {
                                composeController.addAttachmentData(data, mimeType: "application/text", fileName: name)
                            }
                        }
                        arguments.getRootController()?.present(composeController, animated: true, completion: nil)
                    }))
                    
                    actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                        ])])
                    arguments.presentController(actionSheet, nil)
                })
            })
        case let .sendOneLog(theme):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Send Latest Logs (Up to 4 MB)", label: "", sectionId: self.section, style: .blocks, action: {
                let _ = (Logger.shared.collectLogs()
                    |> deliverOnMainQueue).start(next: { logs in
                        let presentationData = arguments.sharedContext.currentPresentationData.with { $0 }
                        let actionSheet = ActionSheetController(presentationData: presentationData)
                        
                        var items: [ActionSheetButtonItem] = []
                        
                        if let context = arguments.context {
                            items.append(ActionSheetButtonItem(title: "Via Telegram", color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                                
                                let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyWriteable, .excludeDisabled]))
                                controller.peerSelected = { [weak controller] peer in
                                    let peerId = peer.id
                                    
                                    if let strongController = controller {
                                        strongController.dismiss()
                                        
                                        let lineFeed = "\n".data(using: .utf8)!
                                        var logData: Data = Data()
                                        
                                        var latestLogs: [(String, String)] = []
                                        if logs.count < 2 {
                                            latestLogs = logs
                                        } else {
                                            for i in (logs.count - 2) ..< logs.count {
                                                latestLogs.append(logs[i])
                                            }
                                        }
                                        
                                        for (name, path) in latestLogs {
                                            if !logData.isEmpty {
                                                logData.append(lineFeed)
                                                logData.append(lineFeed)
                                            }
                                            
                                            logData.append("------ File: \(name) ------\n".data(using: .utf8)!)
                                            
                                            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                                                logData.append(data)
                                            }
                                        }
                                        
                                        let id = arc4random64()
                                        let fileResource = LocalFileMediaResource(fileId: id, size: logData.count, isSecretRelated: false)
                                        context.account.postbox.mediaBox.storeResourceData(fileResource.id, data: logData)
                                        
                                        let file = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: fileResource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/text", size: logData.count, attributes: [.FileName(fileName: "Log-iOS-Short.txt")])
                                        let message: EnqueueMessage = .message(text: "", attributes: [], mediaReference: .standalone(media: file), replyToMessageId: nil, localGroupingKey: nil)
                                        
                                        let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [message]).start()
                                    }
                                }
                                arguments.pushController(controller)
                            }))
                        }
                        
                        items.append(ActionSheetButtonItem(title: "Via Email", color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            
                            let composeController = MFMailComposeViewController()
                            composeController.mailComposeDelegate = arguments.mailComposeDelegate
                            composeController.setSubject("Telegram Logs")
                            for (name, path) in logs {
                                if let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) {
                                    composeController.addAttachmentData(data, mimeType: "application/text", fileName: name)
                                }
                            }
                            arguments.getRootController()?.present(composeController, animated: true, completion: nil)
                        }))
                        
                        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                            })
                            ])
                            ])
                        arguments.presentController(actionSheet, nil)
                    })
            })
        case let .sendShareLogs:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Send Share Logs (Up to 40 MB)", label: "", sectionId: self.section, style: .blocks, action: {
                let _ = (Logger.shared.collectLogs(prefix: "/share-logs")
                |> deliverOnMainQueue).start(next: { logs in
                    let presentationData = arguments.sharedContext.currentPresentationData.with { $0 }
                    let actionSheet = ActionSheetController(presentationData: presentationData)
                    
                    var items: [ActionSheetButtonItem] = []
                    
                    if let context = arguments.context {
                        items.append(ActionSheetButtonItem(title: "Via Telegram", color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            
                            let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyWriteable, .excludeDisabled]))
                            controller.peerSelected = { [weak controller] peer in
                                let peerId = peer.id
                                
                                if let strongController = controller {
                                    strongController.dismiss()
                                    
                                    let lineFeed = "\n".data(using: .utf8)!
                                    var logData: Data = Data()
                                    for (name, path) in logs {
                                        if !logData.isEmpty {
                                            logData.append(lineFeed)
                                            logData.append(lineFeed)
                                        }
                                        
                                        logData.append("------ File: \(name) ------\n".data(using: .utf8)!)
                                        
                                        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                                            logData.append(data)
                                        }
                                    }
                                    
                                    let id = arc4random64()
                                    let fileResource = LocalFileMediaResource(fileId: id, size: logData.count, isSecretRelated: false)
                                    context.account.postbox.mediaBox.storeResourceData(fileResource.id, data: logData)
                                    
                                    let file = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: fileResource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/text", size: logData.count, attributes: [.FileName(fileName: "Log-iOS-Full.txt")])
                                    let message: EnqueueMessage = .message(text: "", attributes: [], mediaReference: .standalone(media: file), replyToMessageId: nil, localGroupingKey: nil)
                                    
                                    let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [message]).start()
                                }
                            }
                            arguments.pushController(controller)
                        }))
                    }
                    items.append(ActionSheetButtonItem(title: "Via Email", color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        
                        let composeController = MFMailComposeViewController()
                        composeController.mailComposeDelegate = arguments.mailComposeDelegate
                        composeController.setSubject("Telegram Logs")
                        for (name, path) in logs {
                            if let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) {
                                composeController.addAttachmentData(data, mimeType: "application/text", fileName: name)
                            }
                        }
                        arguments.getRootController()?.present(composeController, animated: true, completion: nil)
                    }))
                    
                    actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                        ])])
                    arguments.presentController(actionSheet, nil)
                })
            })
        case let .sendNotificationLogs(theme):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Send Notification Logs", label: "", sectionId: self.section, style: .blocks, action: {
                let _ = (Logger(rootPath: arguments.sharedContext.basePath, basePath: arguments.sharedContext.basePath + "/notificationServiceLogs").collectLogs()
                    |> deliverOnMainQueue).start(next: { logs in
                        guard let context = arguments.context else {
                            return
                        }
                        let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyWriteable, .excludeDisabled]))
                        controller.peerSelected = { [weak controller] peer in
                            let peerId = peer.id
                            
                            if let strongController = controller {
                                strongController.dismiss()
                                
                                let messages = logs.map { (name, path) -> EnqueueMessage in
                                    let id = arc4random64()
                                    let file = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: id), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/text", size: nil, attributes: [.FileName(fileName: name)])
                                    return .message(text: "", attributes: [], mediaReference: .standalone(media: file), replyToMessageId: nil, localGroupingKey: nil)
                                }
                                let _ = enqueueMessages(account: context.account, peerId: peerId, messages: messages).start()
                            }
                        }
                        arguments.pushController(controller)
                    })
            })
        case let .sendCriticalLogs(theme):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Send Critical Logs", label: "", sectionId: self.section, style: .blocks, action: {
                let _ = (Logger.shared.collectShortLogFiles()
                    |> deliverOnMainQueue).start(next: { logs in
                        let presentationData = arguments.sharedContext.currentPresentationData.with { $0 }
                        let actionSheet = ActionSheetController(presentationData: presentationData)
                        
                        var items: [ActionSheetButtonItem] = []
                        
                        if let context = arguments.context {
                            items.append(ActionSheetButtonItem(title: "Via Telegram", color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                                
                                let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyWriteable, .excludeDisabled]))
                                controller.peerSelected = { [weak controller] peer in
                                    let peerId = peer.id
                                    
                                    if let strongController = controller {
                                        strongController.dismiss()
                                        
                                        let messages = logs.map { (name, path) -> EnqueueMessage in
                                            let id = arc4random64()
                                            let file = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: id), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/text", size: nil, attributes: [.FileName(fileName: name)])
                                            return .message(text: "", attributes: [], mediaReference: .standalone(media: file), replyToMessageId: nil, localGroupingKey: nil)
                                        }
                                        let _ = enqueueMessages(account: context.account, peerId: peerId, messages: messages).start()
                                    }
                                }
                                arguments.pushController(controller)
                            }))
                        }
                        
                        items.append(ActionSheetButtonItem(title: "Via Email", color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            
                            let composeController = MFMailComposeViewController()
                            composeController.mailComposeDelegate = arguments.mailComposeDelegate
                            composeController.setSubject("Telegram Logs")
                            for (name, path) in logs {
                                if let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) {
                                    composeController.addAttachmentData(data, mimeType: "application/text", fileName: name)
                                }
                            }
                            arguments.getRootController()?.present(composeController, animated: true, completion: nil)
                        }))
                        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                            })
                            ])])
                        arguments.presentController(actionSheet, nil)
                    })
            })
        case let .accounts(theme):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Accounts", label: "", sectionId: self.section, style: .blocks, action: {
                guard let context = arguments.context else {
                    return
                }
                arguments.pushController(debugAccountsController(context: context, accountManager: arguments.sharedContext.accountManager))
            })
        case let .logToFile(theme, value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Log to File", value: value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = updateLoggingSettings(accountManager: arguments.sharedContext.accountManager, {
                    $0.withUpdatedLogToFile(value)
                }).start()
            })
        case let .logToConsole(theme, value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Log to Console", value: value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = updateLoggingSettings(accountManager: arguments.sharedContext.accountManager, {
                    $0.withUpdatedLogToConsole(value)
                }).start()
            })
        case let .redactSensitiveData(theme, value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Remove Sensitive Data", value: value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = updateLoggingSettings(accountManager: arguments.sharedContext.accountManager, {
                    $0.withUpdatedRedactSensitiveData(value)
                }).start()
            })
        case let .enableRaiseToSpeak(theme, value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Enable Raise to Speak", value: value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = updateMediaInputSettingsInteractively(accountManager: arguments.sharedContext.accountManager, {
                    $0.withUpdatedEnableRaiseToSpeak(value)
                }).start()
            })
        case let .keepChatNavigationStack(theme, value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Keep Chat Stack", value: value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = updateExperimentalUISettingsInteractively(accountManager: arguments.sharedContext.accountManager, { settings in
                    var settings = settings
                    settings.keepChatNavigationStack = value
                    return settings
                }).start()
            })
        case let .skipReadHistory(theme, value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Skip read history", value: value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = updateExperimentalUISettingsInteractively(accountManager: arguments.sharedContext.accountManager, { settings in
                    var settings = settings
                    settings.skipReadHistory = value
                    return settings
                }).start()
            })
        case let .crashOnSlowQueries(theme, value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Crash when slow", value: value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = updateExperimentalUISettingsInteractively(accountManager: arguments.sharedContext.accountManager, { settings in
                    var settings = settings
                    settings.crashOnLongQueries = value
                    return settings
                }).start()
            })
        case let .clearTips(theme):
            return ItemListActionItem(presentationData: presentationData, title: "Clear Tips", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                let _ = (arguments.sharedContext.accountManager.transaction { transaction -> Void in
                    transaction.clearNotices()
                }).start()
                if let context = arguments.context {
                    let _ = (context.account.postbox.transaction { transaction -> Void in
                        transaction.clearItemCacheCollection(collectionId: Namespaces.CachedItemCollection.cachedPollResults)
                        unmarkChatListFeaturedFiltersAsSeen(transaction: transaction)
                        
                        transaction.clearItemCacheCollection(collectionId: Namespaces.CachedItemCollection.cachedStickerPacks)
                    }).start()
                }
            })
        case let .reimport(theme):
            return ItemListActionItem(presentationData: presentationData, title: "Reimport Application Data", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                let appGroupName = "group.\(Bundle.main.bundleIdentifier!)"
                let maybeAppGroupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)
                
                guard let appGroupUrl = maybeAppGroupUrl else {
                    return
                }
                
                let statusPath = appGroupUrl.path + "/Documents/importcompleted"
                if FileManager.default.fileExists(atPath: statusPath) {
                    let _ = try? FileManager.default.removeItem(at: URL(fileURLWithPath: statusPath))
                    exit(0)
                }
            })
        case let .resetData(theme):
            return ItemListActionItem(presentationData: presentationData, title: "Reset Data", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                let presentationData = arguments.sharedContext.currentPresentationData.with { $0 }
                let actionSheet = ActionSheetController(presentationData: presentationData)
                actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: "All data will be lost."),
                    ActionSheetButtonItem(title: "Reset Data", color: .destructive, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        let databasePath = arguments.sharedContext.accountManager.basePath + "/db"
                        let _ = try? FileManager.default.removeItem(atPath: databasePath)
                        preconditionFailure()
                    }),
                    ]), ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                        ])])
                arguments.presentController(actionSheet, nil)
            })
        case let .resetDatabase(theme):
            return ItemListActionItem(presentationData: presentationData, title: "Clear Database", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                guard let context = arguments.context else {
                    return
                }
                let presentationData = arguments.sharedContext.currentPresentationData.with { $0 }
                let actionSheet = ActionSheetController(presentationData: presentationData)
                actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: "All secret chats will be lost."),
                    ActionSheetButtonItem(title: "Clear Database", color: .destructive, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        let databasePath = context.account.basePath + "/postbox/db"
                        let _ = try? FileManager.default.removeItem(atPath: databasePath)
                        exit(0)
                        preconditionFailure()
                    }),
                    ]), ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                    ])])
                arguments.presentController(actionSheet, nil)
            })
        case let .resetDatabaseAndCache(theme):
            return ItemListActionItem(presentationData: presentationData, title: "Clear Database and Cache", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                guard let context = arguments.context else {
                    return
                }
                let presentationData = arguments.sharedContext.currentPresentationData.with { $0 }
                let actionSheet = ActionSheetController(presentationData: presentationData)
                actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: "All secret chats will be lost."),
                    ActionSheetButtonItem(title: "Clear Database", color: .destructive, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        let databasePath = context.account.basePath + "/postbox"
                        let _ = try? FileManager.default.removeItem(atPath: databasePath)
                        exit(0)
                        preconditionFailure()
                    }),
                    ]), ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                    ])])
                arguments.presentController(actionSheet, nil)
            })
        case let .resetHoles(theme):
            return ItemListActionItem(presentationData: presentationData, title: "Reset Holes", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                guard let context = arguments.context else {
                    return
                }
                let presentationData = arguments.sharedContext.currentPresentationData.with { $0 }
                let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                arguments.presentController(controller, nil)
                let _ = (context.account.postbox.transaction { transaction -> Void in
                    transaction.addHolesEverywhere(peerNamespaces: [Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel], holeNamespace: Namespaces.Message.Cloud)
                    }
                    |> deliverOnMainQueue).start(completed: {
                        controller.dismiss()
                    })
            })
        case let .reindexUnread(theme):
            return ItemListActionItem(presentationData: presentationData, title: "Reindex Unread Counters", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                guard let context = arguments.context else {
                    return
                }
                let presentationData = arguments.sharedContext.currentPresentationData.with { $0 }
                let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                arguments.presentController(controller, nil)
                let _ = (context.account.postbox.transaction { transaction -> Void in
                    transaction.reindexUnreadCounters()
                }
                |> deliverOnMainQueue).start(completed: {
                    controller.dismiss()
                })
            })
        case let .resetBiometricsData(theme):
            return ItemListActionItem(presentationData: presentationData, title: "Reset Biometrics Data", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                let _ = updatePresentationPasscodeSettingsInteractively(accountManager: arguments.sharedContext.accountManager, { settings in
                    return settings.withUpdatedBiometricsDomainState(nil).withUpdatedShareBiometricsDomainState(nil)
                }).start()
            })
        case let .optimizeDatabase(theme):
            return ItemListActionItem(presentationData: presentationData, title: "Optimize Database", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                guard let context = arguments.context else {
                    return
                }
                let presentationData = arguments.sharedContext.currentPresentationData.with { $0 }
                let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                arguments.presentController(controller, nil)
                let _ = (context.account.postbox.optimizeStorage()
                    |> deliverOnMainQueue).start(completed: {
                        controller.dismiss()
                        
                        let controller = OverlayStatusController(theme: presentationData.theme, type: .success)
                        arguments.presentController(controller, nil)
                    })
            })
        case let .photoPreview(theme, value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Media Preview (Updated)", value: value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = arguments.sharedContext.accountManager.transaction ({ transaction in
                    transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings, { settings in
                        var settings = settings as? ExperimentalUISettings ?? ExperimentalUISettings.defaultSettings
                        settings.chatListPhotos = value
                        return settings
                    })
                }).start()
            })
        case let .knockoutWallpaper(_, value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Knockout Wallpaper", value: value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = arguments.sharedContext.accountManager.transaction ({ transaction in
                    transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings, { settings in
                        var settings = settings as? ExperimentalUISettings ?? ExperimentalUISettings.defaultSettings
                        settings.knockoutWallpaper = value
                        return settings
                    })
                }).start()
            })
        case let .demoVideoChats(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Demo Video", value: value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = arguments.sharedContext.accountManager.transaction ({ transaction in
                    transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings, { settings in
                        var settings = settings as? ExperimentalUISettings ?? ExperimentalUISettings.defaultSettings
                        settings.demoVideoChats = value
                        return settings
                    })
                }).start()
            })
        case let .playerEmbedding(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Player Embedding", value: value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = arguments.sharedContext.accountManager.transaction ({ transaction in
                    transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings, { settings in
                        var settings = settings as? ExperimentalUISettings ?? ExperimentalUISettings.defaultSettings
                        settings.playerEmbedding = value
                        return settings
                    })
                }).start()
            })
        case let .playlistPlayback(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Playlist Playback", value: value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = arguments.sharedContext.accountManager.transaction ({ transaction in
                    transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings, { settings in
                        var settings = settings as? ExperimentalUISettings ?? ExperimentalUISettings.defaultSettings
                        settings.playlistPlayback = value
                        return settings
                    })
                }).start()
            })
        case .voiceConference:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Voice Conference (Test)", label: "", sectionId: self.section, style: .blocks, action: {
                guard let _ = arguments.context else {
                    return
                }
            })
        case let .preferredVideoCodec(_, title, value, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                let _ = arguments.sharedContext.accountManager.transaction ({ transaction in
                    transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings, { settings in
                        var settings = settings as? ExperimentalUISettings ?? ExperimentalUISettings.defaultSettings
                        settings.preferredVideoCodec = value
                        return settings
                    })
                }).start()
            })
        case let .disableVideoAspectScaling(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Video Cropping Optimization", value: !value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = arguments.sharedContext.accountManager.transaction ({ transaction in
                    transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings, { settings in
                        var settings = settings as? ExperimentalUISettings ?? ExperimentalUISettings.defaultSettings
                        settings.disableVideoAspectScaling = !value
                        return settings
                    })
                }).start()
            })
        case let .enableVoipTcp(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Enable VoIP TCP", value: !value, sectionId: self.section, style: .blocks, updated: { value in
                let _ = arguments.sharedContext.accountManager.transaction ({ transaction in
                    transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings, { settings in
                        var settings = settings as? ExperimentalUISettings ?? ExperimentalUISettings.defaultSettings
                        settings.enableVoipTcp = value
                        return settings
                    })
                }).start()
            })
        case let .hostInfo(theme, string):
            return ItemListTextItem(presentationData: presentationData, text: .plain(string), sectionId: self.section)
        case let .versionInfo(theme):
            let bundle = Bundle.main
            let bundleId = bundle.bundleIdentifier ?? ""
            let bundleVersion = bundle.infoDictionary?["CFBundleShortVersionString"] ?? ""
            let bundleBuild = bundle.infoDictionary?[kCFBundleVersionKey as String] ?? ""
            return ItemListTextItem(presentationData: presentationData, text: .plain("\(bundleId)\n\(bundleVersion) (\(bundleBuild))"), sectionId: self.section)
        }
    }
}

private func debugControllerEntries(presentationData: PresentationData, loggingSettings: LoggingSettings, mediaInputSettings: MediaInputSettings, experimentalSettings: ExperimentalUISettings, networkSettings: NetworkSettings?, hasLegacyAppData: Bool) -> [DebugControllerEntry] {
    var entries: [DebugControllerEntry] = []
    
    entries.append(.sendLogs(presentationData.theme))
    entries.append(.sendOneLog(presentationData.theme))
    entries.append(.sendShareLogs)
    entries.append(.sendNotificationLogs(presentationData.theme))
    entries.append(.sendCriticalLogs(presentationData.theme))
    entries.append(.accounts(presentationData.theme))
    
    entries.append(.logToFile(presentationData.theme, loggingSettings.logToFile))
    entries.append(.logToConsole(presentationData.theme, loggingSettings.logToConsole))
    entries.append(.redactSensitiveData(presentationData.theme, loggingSettings.redactSensitiveData))
    
    entries.append(.enableRaiseToSpeak(presentationData.theme, mediaInputSettings.enableRaiseToSpeak))
    entries.append(.keepChatNavigationStack(presentationData.theme, experimentalSettings.keepChatNavigationStack))
    #if DEBUG
    entries.append(.skipReadHistory(presentationData.theme, experimentalSettings.skipReadHistory))
    #endif
    entries.append(.crashOnSlowQueries(presentationData.theme, experimentalSettings.crashOnLongQueries))
    entries.append(.clearTips(presentationData.theme))
    if hasLegacyAppData {
        entries.append(.reimport(presentationData.theme))
    }
    entries.append(.resetData(presentationData.theme))
    entries.append(.resetDatabase(presentationData.theme))
    entries.append(.resetDatabaseAndCache(presentationData.theme))
    entries.append(.resetHoles(presentationData.theme))
    entries.append(.reindexUnread(presentationData.theme))
    entries.append(.optimizeDatabase(presentationData.theme))
    entries.append(.knockoutWallpaper(presentationData.theme, experimentalSettings.knockoutWallpaper))
    entries.append(.demoVideoChats(experimentalSettings.demoVideoChats))
    entries.append(.playerEmbedding(experimentalSettings.playerEmbedding))
    entries.append(.playlistPlayback(experimentalSettings.playlistPlayback))
    
    entries.append(.voiceConference)
    
    let codecs: [(String, String?)] = [
        ("No Preference", nil),
        ("H265", "H265"),
        ("H264", "H264"),
        ("VP8", "VP8"),
        ("VP9", "VP9")
    ]
    
    for i in 0 ..< codecs.count {
        entries.append(.preferredVideoCodec(i, codecs[i].0, codecs[i].1, experimentalSettings.preferredVideoCodec == codecs[i].1))
    }
    
    entries.append(.disableVideoAspectScaling(experimentalSettings.disableVideoAspectScaling))
    entries.append(.enableVoipTcp(experimentalSettings.enableVoipTcp))

    if let backupHostOverride = networkSettings?.backupHostOverride {
        entries.append(.hostInfo(presentationData.theme, "Host: \(backupHostOverride)"))
    }
    entries.append(.versionInfo(presentationData.theme))
    
    return entries
}

public func debugController(sharedContext: SharedAccountContext, context: AccountContext?, modal: Bool = false) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?
    var getRootControllerImpl: (() -> UIViewController?)?
    
    let arguments = DebugControllerArguments(sharedContext: sharedContext, context: context, mailComposeDelegate: DebugControllerMailComposeDelegate(), presentController: { controller, arguments in
        presentControllerImpl?(controller, arguments)
    }, pushController: { controller in
        pushControllerImpl?(controller)
    }, getRootController: {
        return getRootControllerImpl?()
    })
    
    let appGroupName = "group.\(Bundle.main.bundleIdentifier!)"
    let maybeAppGroupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)
    
    var hasLegacyAppData = false
    if let appGroupUrl = maybeAppGroupUrl {
        let statusPath = appGroupUrl.path + "/Documents/importcompleted"
        hasLegacyAppData = FileManager.default.fileExists(atPath: statusPath)
    }
    
    let preferencesSignal: Signal<PreferencesView?, NoError>
    if let context = context {
        preferencesSignal = context.account.postbox.preferencesView(keys: [PreferencesKeys.networkSettings])
        |> map(Optional.init)
    } else {
        preferencesSignal = .single(nil)
    }
    
    let signal = combineLatest(sharedContext.presentationData, sharedContext.accountManager.sharedData(keys: Set([SharedDataKeys.loggingSettings, ApplicationSpecificSharedDataKeys.mediaInputSettings, ApplicationSpecificSharedDataKeys.experimentalUISettings])), preferencesSignal)
    |> map { presentationData, sharedData, preferences -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let loggingSettings: LoggingSettings
        if let value = sharedData.entries[SharedDataKeys.loggingSettings] as? LoggingSettings {
            loggingSettings = value
        } else {
            loggingSettings = LoggingSettings.defaultSettings
        }
        
        let mediaInputSettings: MediaInputSettings
        if let value = sharedData.entries[ApplicationSpecificSharedDataKeys.mediaInputSettings] as? MediaInputSettings {
            mediaInputSettings = value
        } else {
            mediaInputSettings = MediaInputSettings.defaultSettings
        }
        
        let experimentalSettings: ExperimentalUISettings = (sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings] as? ExperimentalUISettings) ?? ExperimentalUISettings.defaultSettings
        
        let networkSettings: NetworkSettings? = preferences?.values[PreferencesKeys.networkSettings] as? NetworkSettings
        
        var leftNavigationButton: ItemListNavigationButton?
        if modal {
            leftNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
                dismissImpl?()
            })
        }
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Debug"), leftNavigationButton: leftNavigationButton, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: debugControllerEntries(presentationData: presentationData, loggingSettings: loggingSettings, mediaInputSettings: mediaInputSettings, experimentalSettings: experimentalSettings, networkSettings: networkSettings, hasLegacyAppData: hasLegacyAppData), style: .blocks)
        
        return (controllerState, (listState, arguments))
    }
    
    
    let controller = ItemListController(sharedContext: sharedContext, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    getRootControllerImpl = { [weak controller] in
        return controller?.view.window?.rootViewController
    }
    return controller
}
