//
//  CkRecord-extensions.swift
//  NN1
//
//  Created by Martin Hruby on 08/04/2020.
//  Copyright © 2020 Martin Hruby FIT. All rights reserved.
//

import Foundation
import CloudKit

//
extension CKRecord {
    // ziskej CKRecord v podobe zakodovaneho obsahu
    var ckEncoded: Data {
        // klasika koder
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        
        // systemove atributy ckrecordu se zakoduji
        encodeSystemFields(with: coder)
        
        //
        coder.finishEncoding()
        
        // vysledkem je balik dat
        return coder.encodedData
    }
}
