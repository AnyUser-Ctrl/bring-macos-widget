import Foundation

struct BringAuthResponse: Decodable {
    let uuid: String
    let publicUuid: String
    let email: String
    let name: String?
    let photoPath: String?
    let bringListUUID: String?
    let accessToken: String
    let refreshToken: String
    let tokenType: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case uuid
        case publicUuid
        case email
        case name
        case photoPath
        case bringListUUID
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct BringTokenRefreshResponse: Decodable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct BringList: Decodable, Hashable, Identifiable {
    let listUuid: String
    let name: String
    let theme: String?

    var id: String { listUuid }
}

struct BringListsResponse: Decodable {
    let lists: [BringList]
}

struct BringItem: Decodable, Hashable, Identifiable {
    let name: String
    let specification: String

    var id: String { name + "|" + specification }

    init(name: String, specification: String) {
        self.name = name
        self.specification = specification
    }

    // Bring returns purchase entries as { uuid, itemId, specification, attributes }
    // — itemId is the human-readable name.
    enum CodingKeys: String, CodingKey {
        case itemId
        case specification
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .itemId)
        self.specification = (try? c.decode(String.self, forKey: .specification)) ?? ""
    }
}

struct BringItemsResponse: Decodable {
    let uuid: String?
    let status: String?
    let purchase: [BringItem]
    let recently: [BringItem]

    private struct Items: Decodable {
        let purchase: [BringItem]
        let recently: [BringItem]
    }

    enum CodingKeys: String, CodingKey {
        case uuid, status, items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.uuid = try? c.decode(String.self, forKey: .uuid)
        self.status = try? c.decode(String.self, forKey: .status)
        let items = try c.decode(Items.self, forKey: .items)
        self.purchase = items.purchase
        self.recently = items.recently
    }
}

struct CachedItems: Codable {
    let listUuid: String
    let listName: String
    let items: [CachedItem]
    let fetchedAt: Date

    struct CachedItem: Codable, Hashable, Identifiable {
        let name: String
        let specification: String
        var id: String { name + "|" + specification }
    }
}

extension BringItem {
    /// Localized catalog name for display. `name` stays the raw catalog key
    /// and must keep being used for icons and ids.
    var localizedName: String { BringArticleNames.displayName(for: name) }
}

struct BringUserSettingsResponse: Decodable {
    struct Entry: Decodable { let key: String; let value: String }
    struct ListSettings: Decodable { let listUuid: String; let usersettings: [Entry] }
    let userlistsettings: [ListSettings]
}
