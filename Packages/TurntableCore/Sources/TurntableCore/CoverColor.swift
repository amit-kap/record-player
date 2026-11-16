import Foundation

/// Picks the colour of a generated album cover from its title, so the same title always gets the same cover.
public enum CoverColor {
    /// A hue between 0 and 1. The title is hashed (FNV-1a over its UTF-8 bytes), then the hash is
    /// scrambled so that similar titles land far apart on the colour wheel. The result does not
    /// change between runs.
    public static func hue(for text: String) -> Double {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        // murmur3 fmix64: spreads every input bit across the whole 64-bit value.
        hash ^= hash >> 33
        hash = hash &* 0xff51afd7ed558ccd
        hash ^= hash >> 33
        hash = hash &* 0xc4ceb9fe1a85ec53
        hash ^= hash >> 33
        // Keep the top 53 bits so the value is exact in a Double and always below 1.
        return Double(hash >> 11) / 9007199254740992.0
    }
}
