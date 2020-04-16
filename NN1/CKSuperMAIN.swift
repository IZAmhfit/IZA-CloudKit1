//
//  CKSuperMAIN.swift
//  NN1
//
//  Created by Martin Hruby on 07/04/2020.
//  Copyright © 2020 Martin Hruby FIT. All rights reserved.
//

import Foundation
import SwiftUI
import CloudKit
import Combine


// ---------------------------------------------------------------------
// Protokol, ktery musi splnovat ovladac nad jednou DB entitou
protocol CKEntityManager {
    // asociovan s timto typem entity
    associatedtype Entity: CKExportable
    
    // dotaz na stav entity na strane lokalni DB
    var itemsToSave: [Entity] { get }
    var itemsToDelete: [Entity] { get }
    
    // nejak zapracuj vysledky dvou CK operaci:
    // 1) save - odeslani lokalnich zmen do CK
    // 2) diffFetch - dotaz na zmeny od posledniho changeTokenu
    func processSaveSync(results: CKSaveSyncResults)
    func processDiffSync(results: CKDiffFetchResults)
}

// ---------------------------------------------------------------------
// Hlavni CK-Konektor aplikace
// ---------------------------------------------------------------------
// Zarizuje:
// 1) Definici RecordsZone
// 2) Definici Subscriptions do CK
// 3) DB operaci save: Lokalni zmeny -> CK
// 4) DB operaci diffSync: Zmeny v CK -> lokal
// ---------------------------------------------------------------------
// Zadna uzivatelska DB operace nebude provedena, dokud se CKSuperMAIN
// neinicializuje (nastane "ready")
class CKSuperMAIN : ObservableObject {
    // ...
    static let shared = CKSuperMAIN()
    
    // zavadim si jednu entitu nad DB typem CKDemo
    let _CKManagedDemo = CKManagedEntity<CKDemo>()
    
    // ref na privatni databazi v ramci implicitniho CK kontejneru
    // public DB me vubec nezajima
    let DB = CKContainer.default().privateCloudDatabase
    
    // drzi referenci na definici explicitni zony
    // soucasne je to taky priznak, ze lze pracovat s privateDB
    // pokud je nil, pak bud:
    // - neslo zalozit zonu a aplikace nemuze bezet,
    // - nebo jsem ve fazi bootovani aplikace a jeste neni jasno
    // o existenci zony
    private var _defZone: CKRecordZone?
    var defZone: CKRecordZone? { _defZone }
    
    // aplikace je pripravena na praci z hlediska napojeni na CK
    var ready: Bool { defZone != nil }
    var subsReady = false
    
    // publikuju priznak:
    // aplikace smi provadet SYNC a DIFF-fetch
    @Published var ckOperationAvailable = true
    
    // ref na bezici operace save & diff
    // tyto operace muzou byt rozbehnuty pouze v jednom provedeni
    private var _runningDiff: CKDiffFetchOperation?
    private var _runningSave: CKSaveSyncOperation?
    
    //
    var _anyOpRunning: Bool { _runningDiff != nil || _runningSave != nil }
    
    // iniciacni sekvence
    // volano z SceneDelegate - argument scene je nanic, ale takhle si
    // znacim, ze funkci lze v programu volat jenom z jednoho mista ;)
    // jakoze se vola z konkretniho kontextu
    func ckConnectionStartup(scene: UIScene) {
        //
        defineZones()
    }
    
    // zona je jasna, jeste vyrid subscription
    // existence subscription neni pro aplikaci kriticky dulezita
    private func _zoneDefinedEvent(zone: CKRecordZone) {
        //
        _defZone = zone
        
        //
        defineSubscription(forEntity: "CKDemo")
    }
    
    // zahaj proces ujisteni se o existenci explicitni RecordZone
    // poznamka: existence explicitni zony je NEZBYTNA pro operaci
    // rozdiloveho fetch (changeServerToken...)
    func defineZones() {
        // takovou bych ji chtel mit
        let _defZone = CKRecordZone(zoneName: "mainPrivateZone")
        
        // pokud mam poznamku, ze uz jsem ji do CK uspesne vytvoril
        if UserDefaults.standard.zoneSaved {
            // ok, jedeme dal
            _zoneDefinedEvent(zone: _defZone)
        } else {
            // zahaj operaci ulozeni/vytvoreni zony
            DB.save(_defZone, completionHandler: { zone, error  in
                // dopadne dobre
                if error == nil {
                    // jedeme v global thread, takze do globalnich dat
                    // aplikace zapisujeme vyhradne prechodem do
                    // mainthread!
                    DispatchQueue.main.async {
                        // a priste uz vime
                        UserDefaults.standard.zoneSaved = true
                        
                        //
                        self._zoneDefinedEvent(zone: _defZone)
                    }
                } else {
                    //
                    // zonu neslo ulozit, coz muze znamenat, ze ji
                    // aplikace zalozila na jinem zarizeni nebo nejede
                    // sit nebo neco... tady by se melo zkoumat to "error"
                    // budeme delat, ze je vsecko ok...TODO
                    DispatchQueue.main.async {
                        // ... pokud zkoumanim error mam jistotu, ze...
                        // TODO
                        UserDefaults.standard.zoneSaved = true
                        
                        //
                        self._zoneDefinedEvent(zone: _defZone)
                    }
                }
            })
        }
    }
    
    //
    func defineSubscription(forEntity: CKRecord.RecordType) {
        // pokud uz mam zonu vyjasnenou
        guard ready else { return }
        
        // zakladam subscription, DB mi bude hlasit zmeny
        let _subs = CKDatabaseSubscription(subscriptionID: "my-subs-all")
        
        // jak se subs bude projevovat jako notifikace
        let _info = CKSubscription.NotificationInfo()
        
        // ticha push-notifikace, nevyzaduje souhlas od uzivatele
        _info.shouldSendContentAvailable = true
        _subs.notificationInfo = _info
        
        // DB operace
        let _op = CKModifySubscriptionsOperation(subscriptionsToSave: [_subs],
                                                 subscriptionIDsToDelete: nil)
        
        // operace modifikace subscriptions neprotestuje, kdyz
        // ukladam subs duplicitne....
        _op.modifySubscriptionsCompletionBlock = { _, _, error in
            //
            if error == nil {
                // vlakna, vlakna, vlakna....
                // veskere hrabani se v globalnich datech aplikace
                // vzdy v main-thread
                DispatchQueue.main.async {
                    //
                    self.subsReady = true
                }
            }
        }
        
        // registruj operaci do fronty k DB
        DB.add(_op)
    }
}


// ---------------------------------------------------------------------
// Save Operation
extension CKSuperMAIN {
    // smi volat pouze CKSaveSyncOperation, proto ji mam jako
    // vstupni argument pro zichr...aby nam to nevolal nekdo jiny ;)
    func saveOperationFinished(operation: CKSaveSyncOperation,
                               results: CKSaveSyncResults)
    {
        // paranoia level == .high
        assert(_runningSave === operation, "divne runningSave")
        
        // predpokladam, ze sem vstupuju hlavnim vlaknem, proto
        // si dovolim vstoupit do jineho objektu
        // TODO: pokud by bylo ovladacu vice, pak to prohnat pres
        // vsecny
        // moderneji: publisher - subscriber
        _CKManagedDemo.processSaveSync(results: results)
        
        // vracim do vychoziho stavu
        _runningSave = nil
        ckOperationAvailable = true
    }
    
    // toto jede hlavnim vlaknem, nemusim tudiz zkoumat
    // vylucnost pristupu nad timto kodem...
    func syncSave() {
        // vstupni straz: zony musi fungovat, zadna bezici operace
        guard ready, _anyOpRunning == false else { return }
    
        // zadani ulohy
        let needs = _CKManagedDemo.itemsToSave
        let needsD = _CKManagedDemo.itemsToDelete
        
        // cksave jeste muze odmitnout nastartovat...to by konstrukce
        // vracela nil
        if let _wouldRUN = CKSaveSyncOperation(withObjects: needs,
                                               toDelete: needsD)
        {
            // registruju operaci, tim uzamykam tento kod
            _runningSave = _wouldRUN
            
            // vypnout tlacitka
            ckOperationAvailable = false
            
            // jedeme
            _wouldRUN.main()
        }
    }
}


// ---------------------------------------------------------------------
// DiffFetch operation - koncept stejny jako u save operace
extension CKSuperMAIN {
    //
    func diffSyncOperationFinished(operation: CKDiffFetchOperation,
                                   results: CKDiffFetchResults)
    {
        // ...
        _CKManagedDemo.processDiffSync(results: results)
        
        // ...
        _runningDiff = nil
        ckOperationAvailable = true
    }
    
    //
    func startDiffSync() {
        // ...
        guard ready, _anyOpRunning == false else { return }
        
        // ...
        if let _wouldRun = CKDiffFetchOperation() {
            //
            _runningDiff = _wouldRun
            
            // ...
            ckOperationAvailable = false
            
            // zahaj operaci
            _wouldRun.sync()
        }
    }
}
