//
//  WebRTC.swift
//  SimpleX (iOS)
//
//  Created by Evgeny on 03/05/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import Foundation

struct WVAPICall: Encodable {
    var corrId: Int
    var command: WCallCommand
}

struct WVAPIMessage: Decodable {
    var corrId: Int?
    var resp: WCallResponse
}

enum WCallCommand {
    case capabilities
    case start(media: CallMediaType, aesKey: String? = nil)
    case accept(offer: String, iceCandidates: [String], media: CallMediaType, aesKey: String? = nil)
    case answer(answer: String, iceCandidates: [String])
    case ice(iceCandidates: [String])
    case end

    enum CodingKeys: String, CodingKey {
        case type
        case media
        case aesKey
        case offer
        case answer
        case iceCandidates
    }
}

extension WCallCommand: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .capabilities:
            try container.encode("capabilities", forKey: .type)
        case let .start(media, aesKey):
            try container.encode("start", forKey: .type)
            try container.encode(media, forKey: .media)
            try container.encode(aesKey, forKey: .aesKey)
        case let .accept(offer, iceCandidates, media, aesKey):
            try container.encode("accept", forKey: .type)
            try container.encode(offer, forKey: .offer)
            try container.encode(iceCandidates, forKey: .iceCandidates)
            try container.encode(media, forKey: .media)
            try container.encode(aesKey, forKey: .aesKey)
        case let .answer(answer, iceCandidates):
            try container.encode("answer", forKey: .type)
            try container.encode(answer, forKey: .answer)
            try container.encode(iceCandidates, forKey: .iceCandidates)
        case let .ice(iceCandidates):
            try container.encode("ice", forKey: .type)
            try container.encode(iceCandidates, forKey: .iceCandidates)
        case .end:
            try container.encode("end", forKey: .type)
        }
    }
}

// This protocol is only needed for debugging
extension WCallCommand: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: CodingKeys.type)
        switch type {
        case "capabilities":
            self = .capabilities
        case "start":
            let media = try container.decode(CallMediaType.self, forKey: CodingKeys.media)
            let aesKey = try? container.decode(String.self, forKey: CodingKeys.aesKey)
            self = .start(media: media, aesKey: aesKey)
        case "accept":
            let offer = try container.decode(String.self, forKey: CodingKeys.offer)
            let iceCandidates = try container.decode([String].self, forKey: CodingKeys.iceCandidates)
            let media = try container.decode(CallMediaType.self, forKey: CodingKeys.media)
            let aesKey = try? container.decode(String.self, forKey: CodingKeys.aesKey)
            self = .accept(offer: offer, iceCandidates: iceCandidates, media: media, aesKey: aesKey)
        case "answer":
            let answer = try container.decode(String.self, forKey: CodingKeys.answer)
            let iceCandidates = try container.decode([String].self, forKey: CodingKeys.iceCandidates)
            self = .answer(answer: answer, iceCandidates: iceCandidates)
        case "ice":
            let iceCandidates = try container.decode([String].self, forKey: CodingKeys.iceCandidates)
            self = .ice(iceCandidates: iceCandidates)
        case "end":
            self = .end
        default:
            throw DecodingError.typeMismatch(WCallCommand.self, DecodingError.Context(codingPath: [CodingKeys.type], debugDescription: "cannot decode WCallCommand, unknown type \(type)"))
        }
    }
}


enum WCallResponse {
    case capabilities(capabilities: CallCapabilities)
    case offer(offer: String, iceCandidates: [String])
    // TODO remove accept, it is needed for debugging
    case accept(offer: String, iceCandidates: [String], media: CallMediaType, aesKey: String? = nil)
    case answer(answer: String, iceCandidates: [String])
    case ice(iceCandidates: [String])
    case connection(state: ConnectionState)
    case ended
    case ok
    case error(message: String)
    case invalid(type: String)

    enum CodingKeys: String, CodingKey {
        case type
        case capabilities
        case offer
        case answer
        case iceCandidates
        case state
        case message
        // TODO remove media, aesKey
        case media
        case aesKey
    }
}

extension WCallResponse: Decodable {
    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: CodingKeys.type)
            switch type {
            case "capabilities":
                let capabilities = try container.decode(CallCapabilities.self, forKey: CodingKeys.capabilities)
                self = .capabilities(capabilities: capabilities)
            case "offer":
                let offer = try container.decode(String.self, forKey: CodingKeys.offer)
                let iceCandidates = try container.decode([String].self, forKey: CodingKeys.iceCandidates)
                self = .offer(offer: offer, iceCandidates: iceCandidates)
            // TODO remove accept
            case "accept":
                let offer = try container.decode(String.self, forKey: CodingKeys.offer)
                let iceCandidates = try container.decode([String].self, forKey: CodingKeys.iceCandidates)
                let media = try container.decode(CallMediaType.self, forKey: CodingKeys.media)
                let aesKey = try? container.decode(String.self, forKey: CodingKeys.aesKey)
                self = .accept(offer: offer, iceCandidates: iceCandidates, media: media, aesKey: aesKey)
            case "answer":
                let answer = try container.decode(String.self, forKey: CodingKeys.answer)
                let iceCandidates = try container.decode([String].self, forKey: CodingKeys.iceCandidates)
                self = .answer(answer: answer, iceCandidates: iceCandidates)
            case "ice":
                let iceCandidates = try container.decode([String].self, forKey: CodingKeys.iceCandidates)
                self = .ice(iceCandidates: iceCandidates)
            case "connection":
                let state = try container.decode(ConnectionState.self, forKey: CodingKeys.state)
                self = .connection(state: state)
            case "ended":
                self = .ended
            case "ok":
                self = .ok
            case "error":
                let message = try container.decode(String.self, forKey: CodingKeys.message)
                self = .error(message: message)
            default:
                self = .invalid(type: type)
            }
        } catch {
            self = .invalid(type: "unknown")
        }
    }
}

// This protocol is only needed for debugging
extension WCallResponse: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .capabilities:
            try container.encode("capabilities", forKey: .type)
        case let .offer(offer, iceCandidates):
            try container.encode("offer", forKey: .type)
            try container.encode(offer, forKey: .offer)
            try container.encode(iceCandidates, forKey: .iceCandidates)
        case let .accept(offer, iceCandidates, media, aesKey):
            try container.encode("accept", forKey: .type)
            try container.encode(offer, forKey: .offer)
            try container.encode(iceCandidates, forKey: .iceCandidates)
            try container.encode(media, forKey: .media)
            try container.encode(aesKey, forKey: .aesKey)
        case let .answer(answer, iceCandidates):
            try container.encode("answer", forKey: .type)
            try container.encode(answer, forKey: .answer)
            try container.encode(iceCandidates, forKey: .iceCandidates)
        case let .ice(iceCandidates):
            try container.encode("ice", forKey: .type)
            try container.encode(iceCandidates, forKey: .iceCandidates)
        case let .connection(state):
            try container.encode("connection", forKey: .type)
            try container.encode(state, forKey: .state)
        case .ended:
            try container.encode("ended", forKey: .type)
        case .ok:
            try container.encode("ok", forKey: .type)
        case let .error(message):
            try container.encode("error", forKey: .type)
            try container.encode(message, forKey: .message)
        case let .invalid(type):
            try container.encode(type, forKey: .type)
        }
    }
}

enum CallMediaType: String, Codable {
    case video = "video"
    case audio = "audio"
}

struct CallCapabilities: Codable {
    var encryption: Bool
}

struct ConnectionState: Codable {
    var connectionState: String
    var iceConnectionState: String
    var iceGatheringState: String
    var signalingState: String
}
