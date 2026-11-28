//
//  PhoneNumberField.swift
//  Kelmteen
//

import SwiftUI

/// A phone number field with a country button next to it ("🇪🇬 +20 ▾ | 0100 123 4567").
///
/// The number is formatted as it's typed. Typing or pasting a full international number
/// ("+44 7700 900123", "0044…") switches the country to match. Use `PhoneNumber.e164(from:region:)`
/// with the same `region` and `nationalNumber` to validate it.
struct PhoneNumberField: View {
    @Binding var region: String
    @Binding var nationalNumber: String

    @Environment(\.locale) private var locale
    @State private var isPickingCountry = false

    private var country: PhoneCountry? { PhoneCountry(region: region) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                isPickingCountry = true
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: country?.flag ?? "🌐")
                    Text(verbatim: "+\(country?.dialCode ?? 0)")
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(country.map { "\($0.name(in: locale)), +\($0.dialCode)" } ?? region))
            .accessibilityHint(Text("Choose your country"))

            Rectangle()
                .fill(Color.ink.opacity(0.15))
                .frame(width: 1, height: 26)

            TextField(text: $nationalNumber, prompt: PhoneNumber.exampleNumber(for: region).map { Text(verbatim: $0) }) {
                Text("Phone number")
            }
            .keyboardType(.phonePad)
            .textContentType(.telephoneNumber)
            .onChange(of: nationalNumber) { handleInput() }
        }
        // Phone numbers always read left to right, even in Arabic.
        .environment(\.layoutDirection, .leftToRight)
        .sheet(isPresented: $isPickingCountry) {
            CountryPickerView(selection: $region)
                // Opened from a left-to-right field, but the list should follow the app's language.
                .environment(\.layoutDirection, AppLanguage.current.layoutDirection)
        }
        .onChange(of: region) {
            nationalNumber = PhoneNumber.formatPartial(nationalNumber, region: region)
        }
    }

    private func handleInput() {
        let text = nationalNumber.westernDigits
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // A full international number: move its country code into the country button.
        if trimmed.hasPrefix("+") || trimmed.hasPrefix("00"),
           let e164 = PhoneNumber.e164(from: trimmed.hasPrefix("00") ? "+" + trimmed.dropFirst(2) : trimmed,
                                       region: region),
           let parts = PhoneNumber.parts(of: e164) {
            region = parts.region
            nationalNumber = parts.national
            return
        }

        let formatted = PhoneNumber.formatPartial(text, region: region)
        if formatted != nationalNumber {
            nationalNumber = formatted
        }
    }
}

/// A searchable list of every country with its flag and dialling code.
struct CountryPickerView: View {
    @Binding var selection: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var query = ""

    private var countries: [PhoneCountry] {
        let sorted = PhoneCountry.all.sorted {
            $0.name(in: locale).localizedStandardCompare($1.name(in: locale)) == .orderedAscending
        }
        let search = query.westernDigits.trimmingCharacters(in: .whitespaces)
        guard !search.isEmpty else { return sorted }
        let digits = search.filter(\.isNumber)
        return sorted.filter { country in
            country.name(in: locale).localizedStandardContains(search)
                || country.region.localizedCaseInsensitiveContains(search)
                || (!digits.isEmpty && String(country.dialCode).hasPrefix(digits))
        }
    }

    var body: some View {
        NavigationStack {
            List(countries) { country in
                Button {
                    selection = country.region
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(verbatim: country.flag)
                            .font(.title2)
                        Text(verbatim: country.name(in: locale))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Text(verbatim: "+\(country.dialCode)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .environment(\.layoutDirection, .leftToRight)
                        if country.region == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityAddTraits(country.region == selection ? .isSelected : [])
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search countries"))
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}
