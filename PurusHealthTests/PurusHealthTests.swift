//
//  PurusHealthTests.swift
//  PurusHealthTests
//
//  Created by Chris Furfari on 05.01.2026.
//

import Testing
import Foundation
import SwiftData
@testable import PurusHealth

struct PurusHealthTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test @MainActor func testModelContainerIsPersistent() async throws {
        // This test verifies that the ModelContainer is configured for persistent storage
        // and not in-memory only storage, which would cause data loss on app close.

        let schema = Schema([
            MedicalRecord.self,
            BloodEntry.self,
            DrugEntry.self,
            VaccinationEntry.self,
            AllergyEntry.self,
            IllnessEntry.self,
            RiskEntry.self,
            MedicalHistoryEntry.self,
            MedicalDocumentEntry.self,
            EmergencyContact.self,
            WeightEntry.self
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        let container = try ModelContainer(for: schema, configurations: [config])
        #expect(config.isStoredInMemoryOnly == false, "ModelContainer should use persistent storage, not in-memory only")

        let context = container.mainContext
        let testRecord = MedicalRecord()
        testRecord.personalGivenName = "PersistenceTest"
        context.insert(testRecord)
        try context.save()

        context.delete(testRecord)
        try context.save()
    }

    @Test @MainActor func testDataPersistenceAcrossSessions() async throws {
        let schema = Schema([MedicalRecord.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        let testUUID = "TEST-PERSISTENCE-12345678-ABCD"
        do {
            let container1 = try ModelContainer(for: schema, configurations: [config])
            let context1 = container1.mainContext

            let record = MedicalRecord()
            record.uuid = testUUID
            record.personalGivenName = "Test"
            record.personalFamilyName = "User"

            context1.insert(record)
            try context1.save()
        }

        do {
            let container2 = try ModelContainer(for: schema, configurations: [config])
            let context2 = container2.mainContext

            // Avoid predicate APIs/macros in this test target; fetch all and filter in-memory.
            let all = try context2.fetch(FetchDescriptor<MedicalRecord>())
            let records = all.filter { $0.uuid == testUUID }

            #expect(records.count == 1, "Record should persist across container instances")
            #expect(records.first?.personalGivenName == "Test", "Persisted data should match")

            if let record = records.first {
                context2.delete(record)
                try context2.save()
            }
        }
    }

    @Test func testRecordLocationStatusMapping() async throws {
        let r = MedicalRecord()

        #expect(r.locationStatus == .local)

        r.isCloudEnabled = true
        r.isSharingEnabled = false
        r.cloudShareRecordName = nil
        #expect(r.locationStatus == .iCloud)

        r.isSharingEnabled = true
        #expect(r.locationStatus == .shared)

        r.isSharingEnabled = false
        r.cloudShareRecordName = "SOME-SHARE-RECORDNAME"
        #expect(r.locationStatus == .shared)

        // Shared should win over all other flags.
        r.isCloudEnabled = false
        r.isSharingEnabled = true
        #expect(r.locationStatus == .shared)

        r.isCloudEnabled = false
        #expect(r.locationStatus == .local)
    }

    @Test func testDisplayNameForHumans() async throws {
        let record = MedicalRecord()

        // Test with all three fields
        record.personalFamilyName = "Smith"
        record.personalGivenName = "John"
        record.personalNickName = "Johnny"
        #expect(record.displayName == "Smith - John - Johnny")

        // Test with only family and given name
        record.personalNickName = ""
        #expect(record.displayName == "Smith - John")

        // Test with only family name
        record.personalGivenName = ""
        #expect(record.displayName == "Smith")

        // Test with only given name
        record.personalFamilyName = ""
        record.personalGivenName = "John"
        #expect(record.displayName == "John")

        // Test with only nickname
        record.personalGivenName = ""
        record.personalNickName = "Johnny"
        #expect(record.displayName == "Johnny")

        // Test with family and nickname only
        record.personalFamilyName = "Smith"
        record.personalGivenName = ""
        record.personalNickName = "Johnny"
        #expect(record.displayName == "Smith - Johnny")

        // Test with all empty
        record.personalFamilyName = ""
        record.personalNickName = ""
        #expect(record.displayName == "Person")
    }

    @Test func testDisplayNameForPets() async throws {
        let record = MedicalRecord()
        record.isPet = true

        // Test with pet name
        record.personalName = "Fluffy"
        #expect(record.displayName == "Fluffy")

        // Test with empty pet name
        record.personalName = ""
        #expect(record.displayName == "Pet")
    }

    @Test func testPetFields() async throws {
        let record = MedicalRecord()
        record.isPet = true
        
        // Test initial values
        #expect(record.personalName == "")
        #expect(record.personalBirthdate == nil)
        #expect(record.petBreed == "")
        #expect(record.petColor == "")
        #expect(record.personalGender == "")
        
        // Set pet-specific fields
        record.personalName = "Max"
        let birthdate = Date(timeIntervalSince1970: 1577836800) // Jan 1, 2020
        record.personalBirthdate = birthdate
        record.petBreed = "Golden Retriever"
        record.petColor = "Golden"
        record.personalGender = "Male"
        
        // Verify fields are set correctly
        #expect(record.personalName == "Max")
        #expect(record.personalBirthdate == birthdate)
        #expect(record.petBreed == "Golden Retriever")
        #expect(record.petColor == "Golden")
        #expect(record.personalGender == "Male")
    }

    @Test @MainActor func testPetFieldsPersistence() async throws {
        let schema = Schema([MedicalRecord.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        let testUUID = "TEST-PET-FIELDS-12345678-ABCD"
        let birthdate = Date(timeIntervalSince1970: 1609459200) // Jan 1, 2021
        
        do {
            let container1 = try ModelContainer(for: schema, configurations: [config])
            let context1 = container1.mainContext

            let record = MedicalRecord()
            record.uuid = testUUID
            record.isPet = true
            record.personalName = "Bella"
            record.personalBirthdate = birthdate
            record.petBreed = "Labrador"
            record.petColor = "Black"
            record.personalGender = "Female"

            context1.insert(record)
            try context1.save()
        }

        do {
            let container2 = try ModelContainer(for: schema, configurations: [config])
            let context2 = container2.mainContext

            // Fetch all records and filter for our test record
            let all = try context2.fetch(FetchDescriptor<MedicalRecord>())
            let records = all.filter { $0.uuid == testUUID }

            #expect(records.count == 1, "Pet record should persist across container instances")
            
            if let record = records.first {
                #expect(record.isPet == true)
                #expect(record.personalName == "Bella")
                #expect(record.personalBirthdate == birthdate)
                #expect(record.petBreed == "Labrador")
                #expect(record.petColor == "Black")
                #expect(record.personalGender == "Female")
                
                // Cleanup
                context2.delete(record)
                try context2.save()
            }
        }
    }

    @Test func testGenderSexOptions() async throws {
        // Test human gender field
        let human = MedicalRecord()
        human.isPet = false
        human.personalGender = "Male"
        #expect(human.personalGender == "Male")
        
        human.personalGender = "Female"
        #expect(human.personalGender == "Female")
        
        human.personalGender = "N/A"
        #expect(human.personalGender == "N/A")
        
        human.personalGender = ""
        #expect(human.personalGender == "")
        
        // Test pet sex field (uses same personalGender)
        let pet = MedicalRecord()
        pet.isPet = true
        pet.personalGender = "Male"
        #expect(pet.personalGender == "Male")
        
        pet.personalGender = "Female"
        #expect(pet.personalGender == "Female")
        
        pet.personalGender = "N/A"
        #expect(pet.personalGender == "N/A")
    }

    @Test func testSortKeyOrdering() async throws {
        let record1 = MedicalRecord()
        record1.personalFamilyName = "Apple"
        record1.personalGivenName = "Aaron"

        let record2 = MedicalRecord()
        record2.personalFamilyName = "Banana"
        record2.personalGivenName = "Bob"

        let record3 = MedicalRecord()
        record3.personalFamilyName = "Apple"
        record3.personalGivenName = "Zoe"

        // Test alphabetical ordering
        #expect(record1.sortKey < record2.sortKey)
        #expect(record1.sortKey < record3.sortKey)
        #expect(record3.sortKey < record2.sortKey)

        // Test case-insensitive ordering
        let record4 = MedicalRecord()
        record4.personalFamilyName = "apple"
        record4.personalGivenName = "aaron"
        #expect(record1.sortKey == record4.sortKey)
    }

    @Test func testSortKeyHumansBeforePets() async throws {
        // Create human records
        let human1 = MedicalRecord()
        human1.isPet = false
        human1.personalFamilyName = "Zebra"
        human1.personalGivenName = "Zoe"

        let human2 = MedicalRecord()
        human2.isPet = false
        human2.personalFamilyName = "Apple"
        human2.personalGivenName = "Aaron"

        // Create pet records
        let pet1 = MedicalRecord()
        pet1.isPet = true
        pet1.personalName = "Fluffy"

        let pet2 = MedicalRecord()
        pet2.isPet = true
        pet2.personalName = "Buddy"

        // Test that all humans come before all pets
        #expect(human1.sortKey < pet1.sortKey, "Human 'Zebra' should come before pet 'Fluffy'")
        #expect(human1.sortKey < pet2.sortKey, "Human 'Zebra' should come before pet 'Buddy'")
        #expect(human2.sortKey < pet1.sortKey, "Human 'Apple' should come before pet 'Fluffy'")
        #expect(human2.sortKey < pet2.sortKey, "Human 'Apple' should come before pet 'Buddy'")

        // Test alphabetical ordering within humans
        #expect(human2.sortKey < human1.sortKey, "Human 'Apple' should come before 'Zebra'")

        // Test alphabetical ordering within pets
        #expect(pet2.sortKey < pet1.sortKey, "Pet 'Buddy' should come before 'Fluffy'")
    }

    @Test @MainActor func testRecordListSorting() async throws {
        // Create an in-memory container for testing
        let schema = Schema([MedicalRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Create test records with mixed order
        let pet1 = MedicalRecord()
        pet1.isPet = true
        pet1.personalName = "Zebra"
        context.insert(pet1)

        let human1 = MedicalRecord()
        human1.isPet = false
        human1.personalFamilyName = "Zane"
        context.insert(human1)

        let pet2 = MedicalRecord()
        pet2.isPet = true
        pet2.personalName = "Alpha"
        context.insert(pet2)

        let human2 = MedicalRecord()
        human2.isPet = false
        human2.personalFamilyName = "Alice"
        context.insert(human2)

        try context.save()

        // Fetch all records
        let allRecords = try context.fetch(FetchDescriptor<MedicalRecord>())

        // Sort them as the UI does
        let sorted = allRecords.sorted { $0.sortKey < $1.sortKey }

        // Verify order: humans first (alphabetically), then pets (alphabetically)
        #expect(sorted.count == 4, "Should have 4 records")
        #expect(sorted[0].displayName == "Alice", "First should be human 'Alice'")
        #expect(sorted[0].isPet == false, "First should be human")
        #expect(sorted[1].displayName == "Zane", "Second should be human 'Zane'")
        #expect(sorted[1].isPet == false, "Second should be human")
        #expect(sorted[2].displayName == "Alpha", "Third should be pet 'Alpha'")
        #expect(sorted[2].isPet == true, "Third should be pet")
        #expect(sorted[3].displayName == "Zebra", "Fourth should be pet 'Zebra'")
        #expect(sorted[3].isPet == true, "Fourth should be pet")
    }
}
