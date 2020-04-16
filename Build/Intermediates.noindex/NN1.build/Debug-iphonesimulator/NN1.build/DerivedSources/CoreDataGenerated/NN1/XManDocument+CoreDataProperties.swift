//
//  XManDocument+CoreDataProperties.swift
//  
//
//  Created by Martin Hruby on 16/04/2020.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension XManDocument {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<XManDocument> {
        return NSFetchRequest<XManDocument>(entityName: "XManDocument")
    }

    @NSManaged public var body: Data?
    @NSManaged public var encoded: Data?
    @NSManaged public var title: String?

}
