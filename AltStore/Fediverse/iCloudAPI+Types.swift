//
//  iCloudAPI+Types.swift
//  AltStore
//
//  Created by Riley Testut on 8/25/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import Foundation
import CloudKit

protocol CloudRecordFields: Codable
{
    static var recordType: CKRecord.RecordType { get }
}

extension iCloudAPI
{
    @dynamicMemberLookup
    struct CloudRecord<Fields: CloudRecordFields>: Identifiable
    {
        static var recordType: CKRecord.RecordType { Fields.recordType }
        var id: CKRecord.ID { self.record.recordID }
        
        private let record: CKRecord
        
        subscript<T>(dynamicMember keyPath: KeyPath<Fields, T>) -> T
        {
            let stringValue = keyPath._kvcKeyPathString!
            
            let value = self.record[stringValue] as! T
            return value
        }
        
        init(record: CKRecord)
        {
            self.record = record
        }
    }

    typealias SourceRecord = CloudRecord<SourceFields>
    typealias NewsItemRecord = CloudRecord<NewsItemFields>

    @objcMembers
    class SourceFields: CloudRecordFields
    {
        static var recordType: CKRecord.RecordType { "Source" }
        
        var sourceID: String
        var url: URL
        var username: String
    }

    @objcMembers
    class NewsItemFields: CloudRecordFields
    {
        static var recordType: CKRecord.RecordType { "NewsItem" }
        
        var identifier: String
        var sourceID: String
        var date: Date
        var statusID: String?
    }
}
