//
//  CKDiffFetchOperation.swift
//  NN1
//
//  Created by Martin Hruby on 08/04/2020.
//  Copyright © 2020 Martin Hruby FIT. All rights reserved.
//

import Foundation
import CloudKit
import Combine

// ---------------------------------------------------------------------
// vysledky operace difffff
struct CKDiffFetchResults {
    // smazany objekt se reportuje dvojici ID a Entita
    typealias DelRecord = (CKRecord.ID, CKRecord.RecordType)
    
    //
    var updated: [CKRecord] = []
    var deleted: [DelRecord] = []
    
    //
    var newToken: CKServerChangeToken?
}

// ---------------------------------------------------------------------
//
class CKDiffFetchOperation {
    // -----------------------------------------------------------------
    // ukladani prubeznych vysledku
    private var _results = CKDiffFetchResults()
    private let _zoneID: CKRecordZone.ID
    
    // -----------------------------------------------------------------
    //
    init?() {
        // muzu se ptat "ready", ale jdu k jadru veci, chci zonu
        guard let _zid = CKSuperMAIN.shared.defZone?.zoneID else {
            //
            return nil
        }
        
        //
        _zoneID = _zid
    }
    
    // -----------------------------------------------------------------
    // udalost o dokonceni prace a predani konecne podoby vysledku
    func sendResult() {
        // implicitni delegate
        CKSuperMAIN.shared.diffSyncOperationFinished(operation: self,
                                                     results: self._results)
    }
    
    // -----------------------------------------------------------------
    // Diff Fetch operace, sestaveni a beh
    func sync() {
        // operace CK, nad PrivateDB, zadana zona
        // poznamka: operace pracuje vyhradne nad explicitni zonou
        let op = CKFetchRecordZoneChangesOperation()
        let conf = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        
        // budu pracovat nad touto zounou
        op.recordZoneIDs = [_zoneID]
        
        // TODO:
        conf.previousServerChangeToken = nil
        
        // ...
        op.configurationsByRecordZoneID = [_zoneID:conf]
        
        // callback pro ukonceni
        op.fetchRecordZoneChangesCompletionBlock = { error in
            // vzdy a vsude...
            DispatchQueue.main.async {
                //
                self.sendResult()
            }
        }
        
        // nad kazdym ziskanym ckrecord
        op.recordChangedBlock = { ckr in
            // tento kod se vykonava buhvijakym vlaknem, ale
            // je mi to jedno, pac na vnitrni data objektu
            // nikdo jiny nemuze
            self._results.updated.append(ckr)
        }
        
        //
        op.recordWithIDWasDeletedBlock = { _rid, _rtype in
            //
            self._results.deleted.append((_rid, _rtype))
        }
        
        // poznac si novy token
        op.recordZoneChangeTokensUpdatedBlock = { _zoneID, _token, _data in
            //
            self._results.newToken = _token
        }
        
        //
        CKSuperMAIN.shared.DB.add(op)
    }
}
