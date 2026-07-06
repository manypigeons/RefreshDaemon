//
//  XPCConnectionHandler.swift
//  AltDaemon
//
//  Created by Riley Testut on 9/14/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//
//  FIX (rootless repackage, 2026-07-06):
//  The original allow-list checked `bundleIdentifier.contains("com.Sidestore.Sidestore")`,
//  which is case-sensitive in Swift. SideStore's actual default bundle identifier is
//  "com.SideStore.SideStore" (capital S in "Store" too), which does NOT match that
//  substring, so the daemon would reject connections from a stock SideStore build.
//  This version lowercases both sides before comparing, so any casing variant
//  (including custom bundle IDs from self-built copies used to dodge Apple's
//  3-free-app sideloading limit) is accepted as long as it contains "sidestore".
//
//  This file will NOT take effect until it's rebuilt via Xcode (the shipped
//  /package/usr/bin/AltDaemon binary already has the old check compiled in).
//

import Foundation
import Security

class XPCConnectionHandler: NSObject, ConnectionHandler
{
    var connectionHandler: ((Connection) -> Void)?
    var disconnectionHandler: ((Connection) -> Void)?

    private let dispatchQueue = DispatchQueue(label: "io.altstore.XPCConnectionListener", qos: .utility)
    private let listeners = XPCConnection.machServiceNames.map { NSXPCListener.makeListener(machServiceName: $0) }

    // Substrings are matched case-insensitively against the connecting process's
    // code-signing identifier.
    private let allowedBundleIdentifierSubstrings = [
        "com.rileytestut.altstore",
        "com.kdt.livecontainer",
        "com.sidestore.sidestore",
    ]

    deinit
    {
        self.stopListening()
    }

    func startListening()
    {
        for listener in self.listeners
        {
            listener.delegate = self
            listener.resume()
        }
    }

    func stopListening()
    {
        self.listeners.forEach { $0.suspend() }
    }
}

private extension XPCConnectionHandler
{
    func disconnect(_ connection: Connection)
    {
        connection.disconnect()

        self.disconnectionHandler?(connection)
    }
}

extension XPCConnectionHandler: NSXPCListenerDelegate
{
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool
    {
        let maximumPathLength = 4 * UInt32(MAXPATHLEN)

        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(maximumPathLength))
        defer { pathBuffer.deallocate() }

        proc_pidpath(newConnection.processIdentifier, pathBuffer, maximumPathLength)

        let path = String(cString: pathBuffer)
        let fileURL = URL(fileURLWithPath: path)

        var code: UnsafeMutableRawPointer?
        defer { code.map { Unmanaged<AnyObject>.fromOpaque($0).release() } }

        var status = SecStaticCodeCreateWithPath(fileURL as CFURL, 0, &code)
        guard status == 0 else { return false }

        var signingInfo: CFDictionary?
        defer { signingInfo.map { Unmanaged<AnyObject>.passUnretained($0).release() } }

        status = SecCodeCopySigningInformation(code, kSecCSInternalInformation | kSecCSSigningInformation, &signingInfo)
        guard status == 0 else { return false }

        // Only accept connections from AltStore, SideStore, or LiveContainer.
        // Comparison is case-insensitive (see fix note at top of file).
        guard
            let codeSigningInfo = signingInfo as? [String: Any],
            let bundleIdentifier = codeSigningInfo["identifier"] as? String
        else { return false }

        let normalizedIdentifier = bundleIdentifier.lowercased()
        guard self.allowedBundleIdentifierSubstrings.contains(where: normalizedIdentifier.contains) else { return false }

        let connection = XPCConnection(newConnection)
        newConnection.invalidationHandler = { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            self.disconnect(connection)
        }

        self.connectionHandler?(connection)

        return true
    }
}
