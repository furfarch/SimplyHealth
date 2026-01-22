import Foundation
import SwiftUI

#if canImport(Contacts)
import Contacts
#endif

/// A lightweight representation of a contact selection we can copy into text fields.
struct ContactPickerResult: Identifiable, Hashable {
    let id: String
    let displayName: String
    let phone: String
    let email: String
    let postalAddress: String

    init(id: String, displayName: String, phone: String, email: String, postalAddress: String) {
        self.id = id
        self.displayName = displayName
        self.phone = phone
        self.email = email
        self.postalAddress = postalAddress
    }

    #if canImport(Contacts)
    init(from contact: CNContact) {
        self.id = contact.identifier

        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        self.displayName = name

        self.phone = contact.phoneNumbers.first?.value.stringValue ?? ""
        self.email = contact.emailAddresses.first.map { String($0.value) } ?? ""

        if let firstAddress = contact.postalAddresses.first?.value {
            self.postalAddress = CNPostalAddressFormatter.string(from: firstAddress, style: .mailingAddress)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            self.postalAddress = ""
        }
    }
    #endif
}

/// iOS-only contact picker wrapper.
///
/// On macOS (or when ContactsUI isn't available), we simply don't offer the picker.
struct ContactPickerButton: View {
    let title: String
    let onPick: (ContactPickerResult) -> Void

    @State private var isPresenting = false

    var body: some View {
        #if canImport(ContactsUI) && (os(iOS) || targetEnvironment(macCatalyst))
        Button(title) {
            isPresenting = true
        }
        .sheet(isPresented: $isPresenting) {
            ContactPickerSheet { result in
                isPresenting = false
                onPick(result)
            }
        }
        #else
        EmptyView()
        #endif
    }
}

#if canImport(ContactsUI) && (os(iOS) || targetEnvironment(macCatalyst))
import ContactsUI

private struct ContactPickerSheet: UIViewControllerRepresentable {
    let onPick: (ContactPickerResult) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator

        // We can copy these fields into our vet UI.
        picker.displayedPropertyKeys = [
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactPostalAddressesKey
        ]

        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (ContactPickerResult) -> Void

        init(onPick: @escaping (ContactPickerResult) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(ContactPickerResult(from: contact))
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            // User cancelled; do nothing.
        }
    }
}
#endif
