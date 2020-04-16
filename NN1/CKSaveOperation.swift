//
//  CKSendingSaveOperation.swift
//  NN1
//
//  Created by Martin Hruby on 08/04/2020.
//  Copyright © 2020 Martin Hruby FIT. All rights reserved.
//

import Foundation
import CloudKit

// ---------------------------------------------------------------------
// vysledky operace save, ktere se rozesilaji ovladacum DB entit
struct CKSaveSyncResults {
    // soupisky objektu a jejich novy stav
    var synced: [CKExportable] = []
    var deleted: [CKExportable] = []
    
    // ... TODO
    var notSynced: [CKExportable] = []
}

// ---------------------------------------------------------------------
// Operace obdrzi soupis objektu (vsech moznych entit, jsou CKExportable)
// Cinnost operace se deli na dve vlakna:
// - mainThread - priprava, nasledny postprocessing
// - global - prace operace (nezalezi na typu fronty a vlakna)
// ---------------------------------------------------------------------
// 1) Priprava - init(...) - vybere si objekty, ktere lze odeslat
// 2) Priprava - main() - inicializuje se CK db operace
// 3) DB operace bezi...na vlakne nezalezi
// 4) DB operace dokonci - modifyRecordsCompletionBlock
// 5) prechazime do MainThread
// 6) postprocessing
// 7) notifikace nadrazene strukture - !!! - tady predpokladam
// globalniho unikatniho implicitnho delegata CKSuperMAIN, takze
// se nevysiluju nejakym registrovanim callbacku
// ---------------------------------------------------------------------
class CKSaveSyncOperation {
    // budu si delat dictionary...
    typealias CKDicMap = [CKRecord.ID: CKExportable]
    
    // -----------------------------------------------------------------
    // pro komfortnejsi zpetne mapovani z CKrec -> Object
    let _inmap: CKDicMap
    
    // zadani mise save: insert|update && delete
    let _toSaveCKs: [CKRecord]
    let _toDeleteCKs: [CKRecord.ID]
    
    // zadani mise je prazdne? 
    var empty: Bool { _toSaveCKs.count + _toDeleteCKs.count == 0 }
    
    // -----------------------------------------------------------------
    // ------ Pracuje v rezimu HLAVNIHO vlakna
    // Dusledek: nikdo mi nemuze hrabnout do dat, nemusim si
    // nic extra zamykat
    init?(withObjects: [CKExportable], toDelete: [CKExportable]) {
        //
        var __dic = CKDicMap()
        var __toSave = [CKRecord]()
        var __toDel = [CKRecord.ID]()
        
        // tady vsechny zamknu a pripravim CKRecords
        for o in withObjects {
            //
            if let _ck = o.getReadyForSaveSync() {
                //
                __dic[_ck.recordID] = o
                __toSave.append(_ck)
            }
        }
        
        //
        for o in toDelete {
            //
            if let _ck = o.getReadyForSaveSync() {
                //
                __dic[_ck.recordID] = o
                __toDel.append(_ck.recordID)
            }
        }
        
        //
        _inmap = __dic
        _toSaveCKs = __toSave
        _toDeleteCKs = __toDel
        
        //
        if empty { return nil }
    }
    
    // -----------------------------------------------------------------
    // ------ Pracuje v rezimu HLAVNIHO vlakna
    //
    func finishme(results: CKSaveSyncResults) {
        //
        CKSuperMAIN.shared.saveOperationFinished(operation: self,
                                                 results: results)
    }
    
    // -----------------------------------------------------------------
    // ------ Pracuje v rezimu HLAVNIHO vlakna
    func postProcessInMainQueue(cksUpdated: [CKRecord],
                                idsDeleted: [CKRecord.ID],
                                error: Error?)
    {
        //
        var _results = CKSaveSyncResults()
        
        // hlavne nezapomenout poslat tuhle zpravu ;)
        defer { finishme(results: _results) }
        
        //
        if let _error = error {
            //
            print("CKSaveOperation, error \(_error)")
        }
        
        // potvrzene CKRecord aktualizovane zaznamy
        for vup in cksUpdated {
            // dohledam si objekt schovany za timto ckrecord
            if let _vup = _inmap[vup.recordID] {
                // a oznamim mu radostnou novinu
                // (on si bere aktualizovanou podobu ckrecord)
                _vup.saveSyncWellSynchronized(with: vup)
                
                //
                _results.synced.append(_vup)
            }
        }
        
        // potvrzena smazani v CloudKit
        for vdel in idsDeleted {
            //
            if let _vdel = _inmap[vdel] {
                //
                _vdel.saveSyncWellDeleted()
                
                //
                _results.deleted.append(_vdel)
            }
        }
        
        // projdu si vse, zjistuju nesynchronizovane jedince
        for (_, ns) in _inmap {
            // porad je uzamceny, soucasne jediny duvod uzamceni je,
            // ze ho zamkla tato operace (jinak TODO)
            if ns.isLocked {
                //
                ns.saveSyncUnlock()
                
                //
                _results.notSynced.append(ns)
            }
        }
    }
    
    // -----------------------------------------------------------------
    // ------ Pracuje v rezimu HLAVNIHO vlakna
    func main() {
        //
        let _sysOp = CKModifyRecordsOperation(recordsToSave: _toSaveCKs,
                                              recordIDsToDelete: _toDeleteCKs)
        
        // ------ Pracuje v rezimu OBECNEHO/Global vlakna
        _sysOp.modifyRecordsCompletionBlock = { (cks, ids, err) in
            // ... takze pro dalsi zpracovani prechazim do hlavniho
            DispatchQueue.main.async {
                //
                if let _err = err {
                    //
                    print("CKSave Sync Op: chyba \(_err)")
                }
                
                // ------ Pracuje v rezimu HLAVNIHO vlakna//
                self.postProcessInMainQueue(cksUpdated: cks ?? [CKRecord](),
                                            idsDeleted: ids ?? [CKRecord.ID](),
                                            error: err)
            }
        }
        
        //
        CKSuperMAIN.shared.DB.add(_sysOp)
    }
}
