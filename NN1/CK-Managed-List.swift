//
//  CK-Managed-List.swift
//  NN1
//
//  Created by Martin Hruby on 07/04/2020.
//  Copyright © 2020 Martin Hruby FIT. All rights reserved.
//

import Foundation
import Combine
import CloudKit

// ---------------------------------------------------------------------
// Ovladac nad lokalnimi daty. Pouze na urovni ulozeni v pameti
// CoreData ovladac by byl mirne slozitejsi
// TODO: chybi podpora vazeb mezi objekty
class CKManagedEntity<Entity:CKExportable> : ObservableObject, CKEntityManager
{
    // tento seznam objektu prezentuji ven
    @Published var listOfObjects = [Entity]()
    
    // CoreData: proved fetch objektu s timto predikatem
    var itemsToDelete: [Entity] {
        //
        listOfObjects.filter { $0.ckState.needsDelSync }
    }
    
    // CoreData
    var itemsToSave: [Entity] {
        //
        listOfObjects.filter { $0.ckState.needsSaveSync }
    }
    
    // vytvoreni noveho objektu
    // 1) lokalne - with==nil
    // 2) jako vysledek nejakeho CKQuery
    func createNew(_ with: CKRecord?) -> Entity {
        //
        let _no = Entity()
        
        //
        if let _with = with {
            //
            _no._setupFrom(withCK: _with)
        }
        
        //
        listOfObjects.append(_no)
        
        //
        return _no
    }
    
    //
    func find(recordID: CKRecord.ID) -> Entity? {
        //
        listOfObjects.first(where: { $0.ckState.ckRecord?.recordID == recordID })
    }
    
    //
    // obsluha operace diff-fetch
    func processDiffSync(results: CKDiffFetchResults) {
        //
        var __newOnes = [CKRecord]()
        
        // zarid smazani techto objektu
        for dd in results.deleted where dd.1 == Entity.ckEntityName {
            //
            if let _found = find(recordID: dd.0) {
                //
                primDelete(anObject: _found)
            }
        }
        
        // aktualizace, zajimam se pouze o objekty me entity
        for nc in results.updated where nc.recordType == Entity.ckEntityName {
            //
            var _found = false
            
            // najdi 
            for lo in listOfObjects {
                //
                if lo.receiveCKUpdateIfYours(with: nc) {
                    //
                    _found = true; break
                }
            }
            
            //
            if _found == false {
                //
                __newOnes.append(nc)
            }
        }
        
        // na zaver doplnim nove
        for no in __newOnes {
            //
            let _ = createNew(no)
        }
    }
    
    //
    private func primDelete(anObject: CKExportable) {
        //
        if let _idx = listOfObjects.firstIndex(where: { $0 === anObject }) {
            //
            listOfObjects.remove(at: _idx)
        }
    }
    
    //
    func processSaveSync(results: CKSaveSyncResults) {
        // TODO: pouze pro sve
        for dels in results.deleted where dels.ckEntity == Entity.ckEntityName {
            //
            primDelete(anObject: dels)
        }
    }
    
    //
    func delete(anObject: Entity) {
        // mam ho vubec v seznamu
        if anObject.markAsDeleted() == false {
            //
            primDelete(anObject: anObject)
        }
    }
}
