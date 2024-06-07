//
//  ChatWallpaper.swift
//  SimpleX (iOS)
//
//  Created by Stanislav on 06.06.2024.
//  Copyright © 2024 SimpleX Chat. All rights reserved.
//

import Foundation
import SwiftUI
import SimpleXChat

public enum PresetWallpaper {
    case cats
    case flowers
    case hearts
    case kids
    case school
    case travel

    var res: UIImage {
        switch self {
        case .cats: UIImage()
        case .flowers: UIImage()
        case .hearts: UIImage()
        case .kids: UIImage()
        case .school: UIImage()
        case .travel: UIImage()
        }
    }

    var filename: String {
        switch self {
        case .cats: "cats"
        case .flowers: "flowers"
        case .hearts: "hearts"
        case .kids: "kids"
        case .school: "school"
        case .travel: "travel"
        }
    }

    var scale: Float {
        switch self {
        case .cats: 0.63
        case .flowers: 0.53
        case .hearts: 0.59
        case .kids: 0.53
        case .school: 0.53
        case .travel: 0.68
        }
    }

    var background: [DefaultTheme: Color] {
        switch self {
        case .cats: wallpaperBackgrounds(light: "#ffF8F6EA")
        case .flowers: wallpaperBackgrounds(light: "#ffE2FFE4")
        case .hearts: wallpaperBackgrounds(light: "#ffFDECEC")
        case .kids: wallpaperBackgrounds(light: "#ffdbfdfb")
        case .school: wallpaperBackgrounds(light: "#ffE7F5FF")
        case .travel: wallpaperBackgrounds(light: "#fff9eeff")
        }
    }

    var tint: [DefaultTheme: Color] {
        switch self {
        case .cats: [
            DefaultTheme.LIGHT: "#ffefdca6".colorFromReadableHex(),
            DefaultTheme.DARK: "#ff4b3b0e".colorFromReadableHex(),
            DefaultTheme.SIMPLEX: "#ff51400f".colorFromReadableHex(),
            DefaultTheme.BLACK: "#ff4b3b0e".colorFromReadableHex()
        ]
        case .flowers: [
            DefaultTheme.LIGHT: "#ff9CEA59".colorFromReadableHex(),
            DefaultTheme.DARK: "#ff31560D".colorFromReadableHex(),
            DefaultTheme.SIMPLEX: "#ff36600f".colorFromReadableHex(),
            DefaultTheme.BLACK: "#ff31560D".colorFromReadableHex()
        ]
        case .hearts: [
            DefaultTheme.LIGHT: "#fffde0e0".colorFromReadableHex(),
            DefaultTheme.DARK: "#ff3c0f0f".colorFromReadableHex(),
            DefaultTheme.SIMPLEX: "#ff411010".colorFromReadableHex(),
            DefaultTheme.BLACK: "#ff3C0F0F".colorFromReadableHex()
        ]
        case .kids: [
            DefaultTheme.LIGHT: "#ffadeffc".colorFromReadableHex(),
            DefaultTheme.DARK: "#ff16404B".colorFromReadableHex(),
            DefaultTheme.SIMPLEX: "#ff184753".colorFromReadableHex(),
            DefaultTheme.BLACK: "#ff16404B".colorFromReadableHex()
        ]
        case .school: [
            DefaultTheme.LIGHT: "#ffCEEBFF".colorFromReadableHex(),
            DefaultTheme.DARK: "#ff0F293B".colorFromReadableHex(),
            DefaultTheme.SIMPLEX: "#ff112f43".colorFromReadableHex(),
            DefaultTheme.BLACK: "#ff0F293B".colorFromReadableHex()
        ]
        case .travel: [
            DefaultTheme.LIGHT: "#ffeedbfe".colorFromReadableHex(),
            DefaultTheme.DARK: "#ff311E48".colorFromReadableHex(),
            DefaultTheme.SIMPLEX: "#ff35204e".colorFromReadableHex(),
            DefaultTheme.BLACK: "#ff311E48".colorFromReadableHex()
        ]
        }
    }

    var colors: [DefaultTheme: ThemeColors] {
        switch self {
        case .cats: [
            DefaultTheme.LIGHT: ThemeColors.from(
                sentMessage: "#fffffaed",
                sentQuote: "#fffaf0d6",
                receivedMessage: "#ffF8F7F4",
                receivedQuote: "#ffefede9"
            ),
            DefaultTheme.DARK: ThemeColors.from(
                sentMessage: "#ff2f2919",
                sentQuote: "#ff473a1d",
                receivedMessage: "#ff272624",
                receivedQuote: "#ff373633"
            ),
            DefaultTheme.SIMPLEX: ThemeColors.from(
                sentMessage: "#ff41371b",
                sentQuote: "#ff654f1c",
                receivedMessage: "#ff272624",
                receivedQuote: "#ff373633"
            ),
            DefaultTheme.BLACK: ThemeColors.from(
                sentMessage: "#ff41371b",
                sentQuote: "#ff654f1c",
                receivedMessage: "#ff1f1e1b",
                receivedQuote: "#ff2f2d27"
            )
        ]
        case .flowers: [
            DefaultTheme.LIGHT: ThemeColors.from(
                sentMessage: "#fff1ffe5",
                sentQuote: "#ffdcf9c4",
                receivedMessage: "#ffF4F8F2",
                receivedQuote: "#ffe7ece7"
            ),
            DefaultTheme.DARK: ThemeColors.from(
                sentMessage: "#ff163521",
                sentQuote: "#ff1B5330",
                receivedMessage: "#ff242523",
                receivedQuote: "#ff353733"
            ),
            DefaultTheme.SIMPLEX: ThemeColors.from(
                sentMessage: "#ff184739",
                sentQuote: "#ff1F6F4B",
                receivedMessage: "#ff242523",
                receivedQuote: "#ff353733"
            ),
            DefaultTheme.BLACK: ThemeColors.from(
                sentMessage: "#ff184739",
                sentQuote: "#ff1F6F4B",
                receivedMessage: "#ff1c1f1a",
                receivedQuote: "#ff282b25"
            )
        ]
        case .hearts: [
            DefaultTheme.LIGHT: ThemeColors.from(
                sentMessage: "#fffff4f4",
                sentQuote: "#ffffdfdf",
                receivedMessage: "#fff8f6f6",
                receivedQuote: "#ffefebeb"
            ),
            DefaultTheme.DARK: ThemeColors.from(
                sentMessage: "#ff301515",
                sentQuote: "#ff4C1818",
                receivedMessage: "#ff242121",
                receivedQuote: "#ff3b3535"
            ),
            DefaultTheme.SIMPLEX: ThemeColors.from(
                sentMessage: "#ff491A28",
                sentQuote: "#ff761F29",
                receivedMessage: "#ff242121",
                receivedQuote: "#ff3b3535"
            ),
            DefaultTheme.BLACK: ThemeColors.from(
                sentMessage: "#ff491A28",
                sentQuote: "#ff761F29",
                receivedMessage: "#ff1f1b1b",
                receivedQuote: "#ff2e2626"
            )
        ]
        case .kids: [
            DefaultTheme.LIGHT: ThemeColors.from(
                sentMessage: "#ffeafeff",
                sentQuote: "#ffcbf4f7",
                receivedMessage: "#fff3fafa",
                receivedQuote: "#ffe4efef"
            ),
            DefaultTheme.DARK: ThemeColors.from(
                sentMessage: "#ff16302F",
                sentQuote: "#ff1a4a49",
                receivedMessage: "#ff252626",
                receivedQuote: "#ff373A39"
            ),
            DefaultTheme.SIMPLEX: ThemeColors.from(
                sentMessage: "#ff1a4745",
                sentQuote: "#ff1d6b69",
                receivedMessage: "#ff252626",
                receivedQuote: "#ff373a39"
            ),
            DefaultTheme.BLACK: ThemeColors.from(
                sentMessage: "#ff1a4745",
                sentQuote: "#ff1d6b69",
                receivedMessage: "#ff1e1f1f",
                receivedQuote: "#ff262b29"
            )
        ]
        case .school: [
            DefaultTheme.LIGHT: ThemeColors.from(
                sentMessage: "#ffeef9ff",
                sentQuote: "#ffD6EDFA",
                receivedMessage: "#ffF3F5F9",
                receivedQuote: "#ffe4e8ee"
            ),
            DefaultTheme.DARK: ThemeColors.from(
                sentMessage: "#ff172833",
                sentQuote: "#ff1C3E4F",
                receivedMessage: "#ff26282c",
                receivedQuote: "#ff393c40"
            ),
            DefaultTheme.SIMPLEX: ThemeColors.from(
                sentMessage: "#ff1A3C5D",
                sentQuote: "#ff235b80",
                receivedMessage: "#ff26282c",
                receivedQuote: "#ff393c40"
            ),
            DefaultTheme.BLACK: ThemeColors.from(
                sentMessage: "#ff1A3C5D",
                sentQuote: "#ff235b80",
                receivedMessage: "#ff1d1e22",
                receivedQuote: "#ff292b2f"
            )
        ]
        case .travel: [
            DefaultTheme.LIGHT: ThemeColors.from(
                sentMessage: "#fffcf6ff",
                sentQuote: "#fff2e0fc",
                receivedMessage: "#ffF6F4F7",
                receivedQuote: "#ffede9ee"
            ),
            DefaultTheme.DARK: ThemeColors.from(
                sentMessage: "#ff33263B",
                sentQuote: "#ff53385E",
                receivedMessage: "#ff272528",
                receivedQuote: "#ff3B373E"
            ),
            DefaultTheme.SIMPLEX: ThemeColors.from(
                sentMessage: "#ff3C255D",
                sentQuote: "#ff623485",
                receivedMessage: "#ff26273B",
                receivedQuote: "#ff3A394F"
            ),
            DefaultTheme.BLACK: ThemeColors.from(
                sentMessage: "#ff3C255D",
                sentQuote: "#ff623485",
                receivedMessage: "#ff231f23",
                receivedQuote: "#ff2c2931"
            )
        ]
        }
    }

    func toType(_ base: DefaultTheme, _ scale: Float? = nil) -> WallpaperType {
        WallpaperType.Preset(
            filename,
            scale ?? themeOverridesDefault.get().first { $0.wallpaper != nil && $0.wallpaper!.preset == filename && $0.base == base }?.wallpaper?.scale ?? 1
        )
    }

    static func from(_ filename: String) -> PresetWallpaper? {
        switch filename {
        case PresetWallpaper.cats.filename: PresetWallpaper.cats
        case PresetWallpaper.flowers.filename: PresetWallpaper.flowers
        case PresetWallpaper.hearts.filename: PresetWallpaper.hearts
        case PresetWallpaper.kids.filename: PresetWallpaper.kids
        case PresetWallpaper.school.filename: PresetWallpaper.school
        case PresetWallpaper.travel.filename: PresetWallpaper.travel
        default: nil
        }
    }
}

func wallpaperBackgrounds(light: String) -> [DefaultTheme : Color] {
    [
        DefaultTheme.LIGHT: light.colorFromReadableHex(),
        DefaultTheme.DARK: "#ff121212".colorFromReadableHex(),
        DefaultTheme.SIMPLEX: "#ff111528".colorFromReadableHex(),
        DefaultTheme.BLACK: "#ff070707".colorFromReadableHex()
    ]
}

public enum WallpaperScaleType/*(val contentScale: ContentScale)*/: Codable {
    case fill/* (ContentScale.Crop)*/
    case fit/* (ContentScale.Fit)*/
    case `repeat`/* (ContentScale.Fit)*/

    var text: String {
        switch self {
        case .fill: "Fill"
        case .fit: "Fit"
        case .repeat: "Repeat"
        }
    }
}

public enum WallpaperType {
//    abstract val scale: Float?
//
//    val image by lazy {
//        val filename = when (this) {
//            is Preset -> filename
//            is Image -> filename
//            else -> return@lazy null
//                }
//        if (filename == "") return@lazy null
//            if (cachedImages[filename] != null) {
//            cachedImages[filename]
//        } else {
//            val res = if (this is Preset) {
//                (PresetWallpaper.from(filename) ?? PresetWallpaper.CATS).res.toComposeImageBitmap()!!
//            } else {
//                try {
//                    // In case of unintentional image deletion don't crash the app
//                    File(getWallpaperFilePath(filename)).inputStream().use { loadImageBitmap(it) }
//                } catch (e: Exception) {
//                    Log.e(TAG, "Error while loading wallpaper file: ${e.stackTraceToString()}")
//                    null
//                }
//            }
//            res?.prepareToDraw()
//            cachedImages[filename] = res ?? return@lazy null
//            res
//        }
//    }

    func sameType(_ other: WallpaperType?) -> Bool {
        if case let .Preset(filename, _) = self, case let .Preset(otherFilename, _) = other { filename == otherFilename }
        else if case .Image = self, case .Image = other { true }
        else if case .Empty = self, case .Empty = other { true }
        else { false }
    }

    func samePreset(other: PresetWallpaper?) -> Bool { if case let .Preset(filename, _) = self, filename == other?.filename { true } else { false } }

    case Preset(_ filename: String, _ scale: Float?)
//                val predefinedImageScale = PresetWallpaper.from(filename)?.scale ?? 1f

    case Image(_ filename: String, _ scale: Float?, _ scaleType: WallpaperScaleType?)

    case Empty

    func defaultBackgroundColor(_ theme: DefaultTheme, _ materialBackground: Color) -> Color {
        if case let .Preset(filename, _) = self {
            (PresetWallpaper.from(filename) ?? PresetWallpaper.cats).background[theme]!
        } else {
            materialBackground
        }
    }

    func defaultTintColor(_ theme: DefaultTheme) -> Color {
        if case let .Preset(filename, _) = self {
            (PresetWallpaper.from(filename) ?? PresetWallpaper.cats).tint[theme]!
        } else if case let .Image(_, _, scaleType) = self, scaleType == WallpaperScaleType.repeat {
            Color.clear
        } else {
            Color.clear
        }
    }

    static var cachedImages: [String: UIImage] = [:]

    static func from(_ wallpaper: ThemeWallpaper?) -> WallpaperType? {
        if wallpaper == nil {
            return nil
        } else if let preset = wallpaper?.preset {
            return WallpaperType.Preset(preset, wallpaper?.scale)
        } else if let imageFile = wallpaper?.imageFile {
            return WallpaperType.Image(imageFile, wallpaper?.scale, wallpaper?.scaleType)
        } else {
            return WallpaperType.Empty
        }
    }
}

