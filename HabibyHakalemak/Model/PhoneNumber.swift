//
//  PhoneNumber.swift
//  Kelmteen
//

import CryptoKit
import Foundation
import PhoneNumberKit

/// Phone number rules for every country, using PhoneNumberKit (Google's libphonenumber data).
///
/// Everything that stores, texts or matches a number goes through here, so it always ends up
/// in the same E.164 form (e.g. "+201001234567"). That matters: contacts are matched by a hash
/// of this exact string, so two spellings of one number must produce the same result.
nonisolated enum PhoneNumber {
    /// Loading the country data is slow, so there's one shared parser. It only reads that
    /// data after loading, so sharing it across threads is safe.
    nonisolated(unsafe) static let utility = PhoneNumberUtility()

    /// Used when nothing better is known, e.g. for contacts before the user has a number.
    static let fallbackRegion = "EG"

    /// The E.164 form of a number typed for (or saved without a country code in) `region`, or
    /// nil if it isn't a valid number there. Numbers typed with a "+" or "00" prefix use their
    /// own country code instead. Sign-up passes `requireMobile`, since codes go out by SMS.
    static func e164(from input: String, region: String, requireMobile: Bool = false) -> String? {
        let text = input.westernDigits.trimmingCharacters(in: .whitespaces)
        guard let number = try? utility.parse(text, withRegion: region, ignoreType: !requireMobile) else {
            return nil
        }
        if requireMobile, ![.mobile, .fixedOrMobile].contains(number.type) {
            return nil
        }
        return utility.format(number, toType: .e164)
    }

    /// Splits an E.164 number into its country and nationally formatted number,
    /// e.g. "+201001234567" → ("EG", "0100 123 4567"), for editing.
    static func parts(of e164: String) -> (region: String, national: String)? {
        guard let number = try? utility.parse(e164, ignoreType: true),
              let region = number.regionID else { return nil }
        return (region, utility.format(number, toType: .national))
    }

    /// The country of an E.164 number, e.g. "EG". Contacts saved without a country code are
    /// read as being in the user's own country.
    static func region(of e164: String) -> String? {
        parts(of: e164)?.region
    }

    /// The default country for the picker: the phone's region if it's a real country,
    /// otherwise Egypt.
    static var defaultRegion: String {
        let deviceRegion = Locale.current.region?.identifier
        if let deviceRegion, utility.countryCode(for: deviceRegion) != nil {
            return deviceRegion
        }
        return fallbackRegion
    }

    /// Formats a partly typed national number for display, e.g. "01001" → "0100 1".
    static func formatPartial(_ input: String, region: String) -> String {
        PartialFormatter(utility: utility, defaultRegion: region, withPrefix: true)
            .formatPartial(input.westernDigits)
    }

    /// An example mobile number for a country, shown as the field's placeholder.
    static func exampleNumber(for region: String) -> String? {
        utility.getFormattedExampleNumber(forCountry: region, ofType: .mobile, withFormat: .national)
    }

    /// Hex SHA-256 of an E.164 number. Must match how the server hashes `profiles.phone`.
    static func hash(_ e164: String) -> String {
        SHA256.hash(data: Data(e164.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// A country in the picker.
struct PhoneCountry: Identifiable, Hashable {
    /// ISO region code, e.g. "EG".
    let region: String
    /// International dialling code, e.g. 20.
    let dialCode: UInt64

    var id: String { region }

    /// The country's flag, built from its region code.
    var flag: String {
        region.unicodeScalars
            .compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }
            .map(String.init)
            .joined()
    }

    func name(in locale: Locale) -> String {
        locale.localizedString(forRegionCode: region) ?? region
    }

    init?(region: String) {
        guard let dialCode = PhoneNumber.utility.countryCode(for: region) else { return nil }
        self.region = region
        self.dialCode = dialCode
    }

    /// Every country that has phone numbers ("001" is for non-geographic numbers).
    static let all: [PhoneCountry] = PhoneNumber.utility.allCountries()
        .filter { $0 != "001" }
        .compactMap(PhoneCountry.init(region:))
}
