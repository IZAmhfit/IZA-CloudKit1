//
//  ContentView.swift
//  NN1
//
//  Created by Martin Hruby on 01/04/2020.
//  Copyright © 2020 Martin Hruby FIT. All rights reserved.
//

import SwiftUI
import Combine
import CoreData
import CloudKit

//
func MOC()->NSManagedObjectContext {
    //
    return (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
}


//
struct CKDemoRow: View {
    //
    @ObservedObject var anItem: CKDemo
    
    //
    var body: some View {
        //
        HStack {
            //
            Text(anItem.ckState.code.rawValue)
            
            //
            VStack {
                //
                TextField("title", text: $anItem.title).disabled(anItem.isLocked)
                TextField("age", value: $anItem.age, formatter: NumberFormatter()).disabled(anItem.isLocked).keyboardType(UIKeyboardType.decimalPad)
            }
        }
    }
}

//
struct NotWorkingCloudSheet: View {
    //
    @Binding var notWorkingCloud: Bool
    
    //
    var body: some View {
        //
        VStack {
            //
            Text("Sorry. Not Clouding.").bold()
            
            //
            Button(action: { self.notWorkingCloud = false }) {
                //
                Text("Oh, OK...")
            }
        }
    }
}

//
struct ContentView: View {
    //
    @ObservedObject var demoList = CKSuperMAIN.shared._CKManagedDemo
    @ObservedObject var SUPER = CKSuperMAIN.shared
    
    //
    @State var notWorkingCloud = false
    
    //
    func addNew() {
        //
        let _no = demoList.createNew(nil)
        
        //
        _no.title = "Nejaka nova vec"
        _no.age = Int.random(in: 0...100)
    }
    
    //
    func callDelete(idxSet: IndexSet) {
        //
        let _objs = idxSet.map { demoList.listOfObjects[$0] }
        
        //
        _objs.forEach { demoList.delete(anObject: $0) }
    }
    
    //
    func sync() {
        //
        guard CKSuperMAIN.shared.ready else {
            //
            self.notWorkingCloud = true; return ;
        }
        
        //
        CKSuperMAIN.shared.syncSave()
    }
    
    //
    func diff() {
        //
        guard CKSuperMAIN.shared.ready else {
            //
            self.notWorkingCloud = true; return ;
        }
        
        //
        CKSuperMAIN.shared.startDiffSync()
    }
    
    //
    func markAllDel() {
        //
        for a in demoList.listOfObjects {
            //
            demoList.delete(anObject: a)
        }
    }
    
    //
    var body: some View {
        //
        NavigationView {
            //
            Form {
                //
                Section(header: Text("Records")) {
                    //
                    ForEach(demoList.listOfObjects, id: \.self) { (ckd:CKDemo) in
                        //
                        CKDemoRow(anItem: ckd)
                    }.onDelete { indSet in
                        //
                        self.callDelete(idxSet: indSet)
                    }
                }
            }
            
            .navigationBarTitle("CKDemos")
            .navigationBarItems(trailing: HStack {
                //
                Button(action: addNew) { Image(systemName: "plus")}
                
                //
                Button(action: sync) { Text("Sync") }
                    .disabled(SUPER.ckOperationAvailable == false)
                
                //
                Button(action: diff) { Text("DiffLoad")}
                    .disabled(SUPER.ckOperationAvailable == false)
                
                //
                Button(action: markAllDel) { Text("AllDel") }
            })
            
            .sheet(isPresented: $notWorkingCloud) {
                //
                NotWorkingCloudSheet(notWorkingCloud: self.$notWorkingCloud)
            }
        }
    }
}
