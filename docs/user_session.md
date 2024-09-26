## Purpose

[UserData::Session](https://ryan-kraay.github.io/stremio-addon-devkit/Stremio/Addon/DevKit/UserData/Session.html) is an over-engineered tool, which allows
the secure encryption and decryption of arbitary user data.  `UserData::Sessions` are designed to be used as [Stremio Addon User Data](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/advanced.md#using-user-data-in-addons).

Features include:
 * Supports the encryption/decryption of _ANY_ content.  This means the payload could be a UID for a user, a JSON string, or a binary stream of data.  Your limits will be maxiumum lengh of the generated url that the Stremio Client supports.
 * The encrypted payload is safe to be included as URLs
 * The Content is encrypted with aes (optionally, enaabled by default)
 * The Content is compressed using lz4 (optionally, enabled by default)
 * Built-in data integrety and tampering detection
 * Uses public/private key encryption


