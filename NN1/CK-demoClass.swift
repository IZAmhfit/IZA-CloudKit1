//
//  CK-demoClass.swift
//  NN1
//
//  Created by Martin Hruby on 07/04/2020.
//  Copyright © 2020 Martin Hruby FIT. All rights reserved.
//

import Foundation
import CloudKit
import UIKit
import SwiftUI
import Combine

//
extension CKRecord {
    
    subscript(key: CKDemo.Keys) -> Any? {
        get {
            return self[key.rawValue]
        }
        set {
            self[key.rawValue] = newValue as? CKRecordValue
        }
    }
}


//
class CKDemo: CKExportable, Hashable, ObservableObject {
    //
    enum Keys : String {
        case title
        case age
        case created
        case picture
    }
    
    //
    static func == (lhs: CKDemo, rhs: CKDemo) -> Bool {
        //
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
    
    //
    func hash(into hasher: inout Hasher) {
        //
        hasher.combine(ObjectIdentifier(self))
    }
    
    
    //
    static var ckEntityName: String = "CKDemo"
    
    //
    @Published var title: String = "" { didSet { evModif() } }
    @Published var age: Int = 0 { didSet { evModif() } }
    @Published var created: Date = Date()
    @Published var picture: UIImage?
    
    //
    var __ckState: CKObjectState = CKObjectState(.local)
    var ckState: CKObjectState { __ckState }
    
    //
    func pingObservers() {
        //
        objectWillChange.send()
    }
    
    //
    func evModif() {
        //
        assert(ckState.isLocked == false)
        
        //
        if ckState.needsSaveSync == false {
            //
            __ckState = ckState.beingModifiedByUser
            
            //
            pingObservers()
        }
    }
    
    //
    func save(to: CKRecord) {
        //
        to[.title] = title
        to[.age] = age
        to[.created] = created
    }
    
    //
    func load(from: CKRecord) {
        //
        title = (from[.title] as? String) ?? ""
        age = (from[.age] as? Int) ?? 0
        created = (from[.created] as? Date) ?? Date()
    }
    
    //
    required init() {
        //
    }
}
