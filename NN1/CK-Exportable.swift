//
//  CK-Exportable.swift
//  NN1
//
//  Created by Martin Hruby on 07/04/2020.
//  Copyright © 2020 Martin Hruby FIT. All rights reserved.
//

import Foundation
import CloudKit
import CoreData

// ---------------------------------------------------------------------
// entity == String
// zone - zvolena zona (ne implicitni)
func newCKRecord(entity: CKRecord.RecordType,
                 zone: CKRecordZone) -> CKRecord
{
    // generuju recordID - unikatni pojmenovani zaznamu
    // zona je soucasti identifikace CKRecordu
    let _rid = CKRecord.ID(recordName: UUID().uuidString,
                           zoneID: zone.zoneID)
    
    // zbrusu novy ...
    return CKRecord(recordType: entity, recordID: _rid)
}


// ---------------------------------------------------------------------
// stavy, ve kterych se lokalni datovy objekt muze nachazet
enum CKObjectStateCode : String {
    // je pouze lokalni, nema CK bratricka
    // mohl byt n-krat modifikovan, neco proste obsahuje
    case local = "Local"
    // byl odeslan do CK, cekame na vyrizeni
    case sentToCK = "BeingSynced"
    // bylo do CK odeslano hlaseni, ze ma byt smazan
    case sentToCKDeleted = "BeingDeleted"
    // je synchronizovan a mame aktualni CKRecord
    // nebyl zatim lokalne modifikovan
    case synchronized = "WellSynced"
    // lokalne modifikovan, ale existuje i v CK
    case modified = "Modified"
    // syncFailed, je potreba nacist original z CK
    case syncFailed = "SyncFailed"
    // lokalne smazano, ceka na likvidaci patricnym DB ovladacem
    case deleted = "Del-Marked"
}


// ---------------------------------------------------------------------
// komplexni stav objektu
// pozn.: bylo by stylovejsi sloucit ten enum a tuhle struct,
// ale to snad v pristim zivote ;)
// case modified(CKRecord), ...
// vetsina case by mela argument ck, tak proc to neudelat konvencne
struct CKObjectState {
    // kod stavu
    let code: CKObjectStateCode
    
    // vyznam hodnoty v jednotlivych stavech:
    // .local -> nil
    // .sentToCK -> CK v dobe odeslani save operace
    // .synchronized -> CK po potvrzene operaci save nebo po fetchi
    // .modified -> posledni znamy platny stav CK
    let ckRecord: CKRecord?
    
    // kdyz se nastavi sent, pak se na neho zadnou
    // dalsi operaci nesmi sahnout
    var isLocked: Bool { code == .sentToCK || code == .sentToCKDeleted }
    var isDeleted: Bool { code == .deleted }
    var isLocalOnly: Bool { code == .local }
    
    //
    var needsSaveSync: Bool {
        //
        code == .local || code == .modified || code == .syncFailed
    }
    
    //
    var needsDelSync: Bool {
        //
        code == .deleted
    }
    
    //
    var beingModifiedByUser: CKObjectState {
        //
        if isDeleted || isLocked { return self }
        
        //
        return CKObjectState(.modified, ck: ckRecord)
    }
    
    //
    init(_ st: CKObjectStateCode, ck: CKRecord? = nil) {
        //
        code = st; ckRecord = ck
    }
}


// ---------------------------------------------------------------------
// CK-exportovatelny objekt (class, NSManagedObject)
protocol CKExportable : class {
    // muze byt pohromade, ja pouze zapisovou operaci
    // chci mit zvyraznenou v kodu __
    var ckState: CKObjectState { get }
    var __ckState: CKObjectState { get set }
    
    // jak se ta vec jmenuje na strane CK
    static var ckEntityName: String { get }
    
    // primitivni operace:
    // uloz uzivatelsky obsah do CKRecordu
    // nacti uzivatelsky ...
    func save(to: CKRecord)
    func load(from: CKRecord)
    
    // notifikuj sledovace datoveho objektu
    func pingObservers();
    
    //
    init()
}


// ---------------------------------------------------------------------
// Abstraktni funkcionalita nad protokolem
extension CKExportable {
    //
    var isLocked: Bool { ckState.isLocked }
    
    //
    var ckEntity: CKRecord.RecordType? { ckState.ckRecord?.recordType }
    
    // konstrukce objektu z CKRecordu, tj vcetne instanciace
    // volano z ovladace entity
    func _setupFrom(withCK: CKRecord) {
        //
        load(from: withCK)
        
        //
        __ckState = CKObjectState(.synchronized, ck: withCK)
    }
    
    // zajisti platny CKRecord
    internal var _ckRecordForSaving: CKRecord? {
        //
        guard let _zone = CKSuperMAIN.shared.defZone else { return nil }
        
        // objekt je ve stavu "nove lokalne vytvoreno", tj
        // nema historicky CKRecord, tudiz nove vytvorim
        if ckState.code == .local {
            //
            let _rid = CKRecord.ID(recordName: UUID().uuidString,
                                   zoneID: _zone.zoneID)
            
            // zbrusu novy ...
            let _ck = CKRecord(recordType: Self.ckEntityName, recordID: _rid)
            
            //
            return _ck
        }
        
        //
        return ckState.ckRecord
    }
    
    // zmena stavu objektu do stavu "jsem synchronizovan"
    func getReadyForSaveSync() -> CKRecord? {
        // velky, velky error
        if ckState.isLocked { return nil }
        
        // dalsi velky error
        guard let _ck = _ckRecordForSaving else { return nil }
        
        //
        switch ckState.code {
        case .modified, .local:
            //
            save(to: _ck)
            //
            __ckState = CKObjectState(.sentToCK, ck: _ck)
            
        case .deleted:
            //
            __ckState = CKObjectState(.sentToCKDeleted, ck: _ck)
            
        default:
            // neni duvod synchronizovat
            return nil
        }
        
        // menim stav objektu, pingni...
        pingObservers()
        
        //
        return _ck
    }
    
    //
    func saveSyncWellSynchronized(with: CKRecord) {
        // ani radsi nezkoumam stav, teoreitcky ma byt locked
        __ckState = CKObjectState(.synchronized, ck: with)
        
        //
        pingObservers()
    }
    
    //
    func saveSyncWellDeleted() {
        // nadale je povazovan ze existujiciho pouze lokalne
        // a je urcen pro smazani
        __ckState = CKObjectState(.local, ck: nil)
        
        //
        pingObservers()
    }
    
    //
    func saveSyncUnlock() {
        //
        print("Kvuli chybe prenos musim vratit zamek zpatky bez sync")
        
        //
        switch ckState.code {
            //
        case .sentToCK:
            __ckState = CKObjectState(.modified, ck: ckState.ckRecord)
            
            //
        case .sentToCKDeleted:
            __ckState = CKObjectState(.deleted, ck: ckState.ckRecord)
        
        default:
            //
            abort()
        }
        
        //
        pingObservers()
    }
    
    // humorna metoda
    // iteruje se pres vsechny objekty a ukazuje se jim tenhle ck
    // pokud se k nemu hlasi, je jejich
    func receiveCKUpdateIfYours(with: CKRecord) -> Bool {
        // je to ckrecord patrici ke me?
        if ckState.ckRecord?.recordID == with.recordID {
            // nacti
            load(from: with)
            
            // ...
            __ckState = CKObjectState(.synchronized, ck: with)
            
            // hlas vyse, ze uz netreba hledat
            return true
        }
        
        //
        return false
    }
    
    // je treba neco podniknout, kdyz mazu tento objekt
    func markAsDeleted() -> Bool {
        // ...
        assert(isLocked == false)
        
        // pokud je veden jako lokalni, pak ne
        if ckState.isLocalOnly {
            //
            return false
        }
        
        // jinak ho hod do stavu "oznacen ke smazeni"
        __ckState = CKObjectState(.deleted, ck: ckState.ckRecord)
        pingObservers()
        
        //
        return true;
    }
}

