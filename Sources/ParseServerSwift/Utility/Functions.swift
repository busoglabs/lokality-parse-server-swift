//
//  Functions.swift
//  
//
//  Created by Corey E. Baker on 6/21/22.
//

import ParseSwift
import Vapor

/**
 Sets the `ParseServerSwift` configuration if it has not already been set.
 - parameter configuration: The ParseServer configuration.
 - throws: An error of `ParseError` type.
 - important: If you are using the default
 `ParseServerSwift.initialize()` method, you do not need
 call this method. This is only needed if you are writing a custom
 `ParseServerSwift.initialize()`.
 - warning: This should only be called once as it will throw an error
 if the configuration is already set.
 */
public func setConfiguration(_ configuration: ParseServerConfiguration) throws {
    guard Parse.configuration == nil else {
        throw ParseError(code: .otherCause,
                         message: "The configuration has already been initialized")
    }
    Parse.configuration = configuration
}

/**
 Checks headers for matching webhookKey to prove authenticity.
 - parameter req: The incoming request.
 - returns: **nil** if the webhookKeys match or a `ParseHookResponse`
 with an error that should be sent back to the Parse Server immediately.
 */
public func checkHeaders<T>(_ req: Request) -> ParseHookResponse<T>? {
    // Fails CLOSED. This used to be `header == configuration.webhookKey` on two
    // Optionals, so a server started with no key accepted a request that sent
    // no header (nil == nil) — every hook open to anyone who could reach it.
    guard webhookKeyMatches(req.headers.first(name: Headers.webhook),
                            configured: configuration.webhookKey) else {
        let error = ParseError(code: .otherCause,
                               message: "Webhook keys don't match")
        return ParseHookResponse<T>(error: error)
    }
    return nil
}

/**
 True only when both keys are non-empty and equal. Compared in constant time
 for equal lengths, so response timing does not reveal how much of a guess
 was right.
 */
public func webhookKeyMatches(_ supplied: String?, configured: String?) -> Bool {
    guard let supplied, let configured, !supplied.isEmpty, !configured.isEmpty else {
        return false
    }
    let a = Array(supplied.utf8), b = Array(configured.utf8)
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<a.count { diff |= a[i] ^ b[i] }
    return diff == 0
}

/**
 Returns the correct Parse Server `URL` string related to a particular `URI`.
 - parameter uri: The `URI` to check against.
 - parameter parseServerURLStrings: A set of Parse Server `URL`'s
 to check the `URI` against. Defaults to the set of servers added during configuration.
 - returns: The the Parse Server `URL` string related to a `URI`.
 - throws: An error of `ParseError` type.
 */
public func serverURLString(_ uri: URI,
                            parseServerURLStrings: [String]) throws -> String {
    guard let returnURLString = parseServerURLStrings.first else {
        throw ParseError(code: .otherCause,
                         message: "Missing at least one Parse Server URL")
    }
    return parseServerURLStrings.first(where: { uri.string.contains($0) }) ?? returnURLString
}

/**
 Construct the full server pathname with route.
 - returns: The server path with scheme, hostname, port, and route.
 - throws: An error of `ParseError` type.
 */
public func buildServerPathname(_ path: [PathComponent]) throws -> URL {
    let pathString = "/" + path.map { "\($0)" }.joined(separator: "/")
    guard let url = URL(string: configuration.serverPathname)?.appendingPathComponent(pathString) else {
        throw ParseError(code: .otherCause,
                         message: "Cannot create a pathname for the server")
    }
    return url
}

/// Check the Health of all Parse Servers.
/// - throws: An error of `ParseError` type.
public func checkServerHealth() async throws {
    for parseServerURLString in configuration.parseServerURLStrings {
        do {
            let serverHealth = try await ParseServer.health(options: [.serverURL(parseServerURLString)])
            configuration.logger.notice("Parse Server (\(parseServerURLString)) health is \"\(serverHealth)\"")
        } catch {
            configuration.logger.error("Could not connect to Parse Server (\(parseServerURLString)): \(error)")
            throw error
        }
    }
}

/// Delete all Parse Hooks from all Parse Servers.
/// - parameter app: Core type representing a Vapor application.
public func deleteHooks(_ app: Application) async {
    let functions = await configuration.hooks.getFunctions()
    let triggers = await configuration.hooks.getTriggers()

    app.logger.notice("Deleting Hooks from all Parse Servers, please wait...")

    for (urlString, function) in functions {
        do {
            try await function.delete(options: [.serverURL(urlString)])
            app.logger.notice("Successfully removed Hook Function: \(function); on Parse Server: (\(urlString))")
        } catch {
            // swiftlint:disable:next line_length
            app.logger.error("Could not remove Hook Function: \(function); on Parse Server: (\(urlString)); due to error: \(error)")
        }
        await configuration.hooks.removeFunctions([urlString])
    }

    for (urlString, trigger) in triggers {
        do {
            try await trigger.delete(options: [.serverURL(urlString)])
            app.logger.notice("Successfully removed Hook Trigger: \(trigger); on Parse Server: (\(urlString))")
        } catch {
            // swiftlint:disable:next line_length
            app.logger.error("Could not remove Hook Trigger: \(trigger); on Parse Server: (\(urlString)); due to error: \(error)")
        }
        await configuration.hooks.removeTriggers([urlString])
    }
}

/**
 Get all of the current Parse Server URL's from a String.
 - parameter urls: A string of comma seperated URL's.
 The last url in the string will be used as the main server url.
 - returns: A tuple where the first item is the main server url
 and the second item is an array of the rest of the server urls.
 - throws: An error of `ParseError` type.
 */
public func getParseServerURLs(_ urls: String? = nil) throws -> (String, [String]) {
    let serverURLs = urls ?? Environment.process.PARSE_SERVER_SWIFT_URLS ?? "http://localhost:1337/parse"
    var allServers = serverURLs.replacingOccurrences(of: " ", with: "").split(separator: ",").compactMap { String($0) }
    guard let mainServer = allServers.popLast() else {
        throw ParseError(code: .otherCause, message: "At least 1 server URL is required")
    }
    return (mainServer, allServers)
}

/**
 Construct the full server pathname.
 - parameter configuration: Engine server config struct.
 - returns: The server path with scheme, hostname, and port.
 */
public func buildServerURL(from configuration: HTTPServer.Configuration) -> String {
    let scheme = configuration.tlsConfiguration == nil ? "http" : "https"
    let addressDescription: String
    switch configuration.address {
    case .hostname(let hostname, let port):
        addressDescription = "\(scheme)://\(hostname ?? configuration.hostname):\(port ?? configuration.port)"
    case .unixDomainSocket(let socketPath):
        addressDescription = "\(scheme)+unix: \(socketPath)"
    }
    return addressDescription
}
