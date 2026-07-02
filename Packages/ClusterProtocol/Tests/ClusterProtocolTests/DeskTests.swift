import Foundation
import Testing

@testable import ClusterProtocol

@Suite struct ItemCatalogTests {
    @Test func idsAndSpritesAreUnique() {
        let ids = ItemCatalog.all.map(\.id)
        let sprites = ItemCatalog.all.map(\.spriteIndex)
        #expect(Set(ids).count == ids.count)
        #expect(Set(sprites).count == sprites.count)
    }

    @Test func catalogHasAHealthySpread() {
        #expect(ItemCatalog.all.count == 20)
        for category in CatalogItem.Category.allCases {
            #expect(ItemCatalog.all.contains { $0.category == category })
        }
        #expect(ItemCatalog.item(id: 1) != nil)
        #expect(ItemCatalog.item(id: 999) == nil)
    }
}

@Suite struct DeskCodecTests {
    @Test(arguments: [
        DeskCommand.claim(zone: "desk-01"),
        .release(zone: "desk-01"),
        .place(zone: "desk-03", catalogID: 15, x: 10.5, y: 11, rotation: 2),
        .remove(itemID: 77),
        .move(itemID: 77, x: 12, y: 12.5, rotation: 1),
    ])
    func commandsRoundTrip(_ command: DeskCommand) throws {
        #expect(try DeskCommand(decoding: command.encoded()) == command)
    }

    @Test func stateRoundTrips() throws {
        let state = DeskState(
            claims: [
                DeskClaim(zone: "desk-01", ownerID: "aa11"),
                DeskClaim(zone: "desk-02", ownerID: ""),
            ],
            items: [
                PlacedItem(id: 1, zone: "desk-01", catalogID: 5, x: 10, y: 11.5, rotation: 0),
                PlacedItem(id: 9, zone: "desk-01", catalogID: 16, x: 10.5, y: 11, rotation: 3),
            ])
        #expect(try DeskState(decoding: state.encoded()) == state)
        #expect(try DeskState(decoding: DeskState().encoded()) == DeskState())
    }

    @Test func stateRidesSessionMessages() throws {
        let state = DeskState(claims: [DeskClaim(zone: "desk-05", ownerID: "bb22")])
        let message = SessionMessage.deskState(state)
        #expect(try SessionMessage(decoding: message.encoded()) == message)

        let command = SessionMessage.deskCommand(.claim(zone: "desk-05"))
        #expect(try SessionMessage(decoding: command.encoded()) == command)
    }
}

@Suite struct DeskStateQueryTests {
    let state = DeskState(
        claims: [
            DeskClaim(zone: "desk-01", ownerID: "ricardo"),
            DeskClaim(zone: "desk-02", ownerID: ""),
        ],
        items: [
            PlacedItem(id: 1, zone: "desk-01", catalogID: 5, x: 1, y: 1, rotation: 0),
            PlacedItem(id: 2, zone: "desk-03", catalogID: 6, x: 2, y: 2, rotation: 0),
        ])

    @Test func ownershipQueries() {
        #expect(state.owner(of: "desk-01") == "ricardo")
        #expect(state.owner(of: "desk-02") == nil)  // empty owner = unclaimed
        #expect(state.owner(of: "desk-99") == nil)
        #expect(state.deskOwned(by: "ricardo") == "desk-01")
        #expect(state.deskOwned(by: "nobody") == nil)
    }

    @Test func itemsByZone() {
        #expect(state.items(in: "desk-01").map(\.id) == [1])
        #expect(state.items(in: "desk-02").isEmpty)
    }
}

@Suite struct DeskRulesTests {
    let zone = WorldMap.Zone(name: "desk-01", type: "desk", x: 10, y: 12, width: 1, height: 1)

    @Test func insideBoundsIncludesEdges() {
        #expect(DeskRules.isInside(x: 10, y: 12, zone: zone))
        #expect(DeskRules.isInside(x: 11, y: 13, zone: zone))
        #expect(DeskRules.isInside(x: 10.5, y: 12.5, zone: zone))
        #expect(!DeskRules.isInside(x: 9.9, y: 12, zone: zone))
        #expect(!DeskRules.isInside(x: 10, y: 13.1, zone: zone))
    }

    @Test func snapHitsHalfTiles() {
        #expect(DeskRules.snap(x: 10.24, y: 12.6).x == 10.0)
        #expect(DeskRules.snap(x: 10.26, y: 12.6).y == 12.5)
        #expect(DeskRules.snap(x: 10.76, y: 12.99).x == 11.0)
        #expect(DeskRules.snap(x: 10.76, y: 12.99).y == 13.0)
    }

    @Test func capIsSane() {
        #expect(DeskRules.maxItemsPerDesk >= 4 && DeskRules.maxItemsPerDesk <= 16)
    }

    @Test func deskZoneLookupFiltersByType() throws {
        let json = """
            {"width":3,"height":2,"tilewidth":32,
             "layers":[
               {"name":"floor","type":"tilelayer","data":[1,1,1,1,1,1]},
               {"name":"walls","type":"tilelayer","data":[0,0,0,0,0,0]},
               {"name":"objects","type":"objectgroup","objects":[
                 {"name":"spawn","type":"spawn","x":32.0,"y":32.0},
                 {"name":"desk-01","type":"desk","x":64.0,"y":0.0,"width":32.0,"height":32.0},
                 {"name":"desk-01","type":"kart-track","x":0.0,"y":0.0,"width":96.0,"height":64.0}]}],
             "tilesets":[{"firstgid":1}]}
            """
        let map = try TiledMapLoader.load(data: Data(json.utf8))
        let zone = try #require(DeskRules.deskZone(named: "desk-01", in: map))
        #expect(zone.type == "desk")
        #expect(zone.x == 2 && zone.width == 1)
        #expect(DeskRules.deskZone(named: "desk-99", in: map) == nil)
    }
}
