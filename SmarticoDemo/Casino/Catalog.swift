import Foundation

/**
 * Fake-slot catalog, ported from the web fake-casino (casino-games.js) via the
 * React Native demo.
 *
 * Each game is six AVIF files: a thumbnail, a static frame, and four play-once
 * transition sprites. The sprite IS the game — there is no reel engine, the
 * outcome is decided by the bet/multiplier the player dials in. File names are
 * theme-suffixed with inconsistent casing; do not "fix" them.
 */
struct CasinoGame: Hashable, Sendable {
    let extId: String
    let name: String
    let thumbnail: String
    let staticImg: String
    let lossToLoss: String
    let lossToWin: String
    let winToLoss: String
    let winToWin: String
    let categories: [String]
}

/** Assets are served by the deployed fake-casino. */
let ASSET_BASE = "https://play.smartico.ai/"

func gameAsset(_ path: String) -> String { ASSET_BASE + path }

let casinoGames: [CasinoGame] = [
    CasinoGame(
        extId: "treasure-seeker",
        name: "Treasure Seeker",
        thumbnail: "casino-games/animations/Pirates/pirate_game_thumbnail.avif",
        staticImg: "casino-games/animations/Pirates/static.avif",
        lossToLoss: "casino-games/animations/Pirates/loss-to-loss.avif",
        lossToWin: "casino-games/animations/Pirates/loss-to-win.avif",
        winToLoss: "casino-games/animations/Pirates/win-to-loss.avif",
        winToWin: "casino-games/animations/Pirates/win-to-win.avif",
        categories: ["All"]
    ),
    CasinoGame(
        extId: "dragon-fortune",
        name: "Dragon Fortune",
        thumbnail: "casino-games/animations/China/china.avif",
        staticImg: "casino-games/animations/China/static-china.avif",
        lossToLoss: "casino-games/animations/China/loss-to-loss-China.avif",
        lossToWin: "casino-games/animations/China/loss-to-win-China.avif",
        winToLoss: "casino-games/animations/China/win-to-loss-China.avif",
        winToWin: "casino-games/animations/China/win-to-win-China.avif",
        categories: ["All"]
    ),
    CasinoGame(
        extId: "ocean-riches",
        name: "Ocean Riches",
        thumbnail: "casino-games/animations/clam-game/clam_game_thumbnail.avif",
        staticImg: "casino-games/animations/clam-game/static.avif",
        lossToLoss: "casino-games/animations/clam-game/loss-to-loss.avif",
        lossToWin: "casino-games/animations/clam-game/loss-to-win.avif",
        winToLoss: "casino-games/animations/clam-game/win-to-loss.avif",
        winToWin: "casino-games/animations/clam-game/win-to-win.avif",
        categories: ["Top", "All"]
    ),
    CasinoGame(
        extId: "donut-delight",
        name: "Donut Delight",
        thumbnail: "casino-games/animations/Donuts/donuts_game_thumbnail.avif",
        staticImg: "casino-games/animations/Donuts/static-donuts.avif",
        lossToLoss: "casino-games/animations/Donuts/loss-to-loss-donuts.avif",
        lossToWin: "casino-games/animations/Donuts/loss-to-win-donuts.avif",
        winToLoss: "casino-games/animations/Donuts/win-to-loss-donuts.avif",
        winToWin: "casino-games/animations/Donuts/win-to-win-donuts.avif",
        categories: ["Top", "All"]
    ),
    CasinoGame(
        extId: "pharaohs-fortune",
        name: "Pharahs Fortune",
        thumbnail: "casino-games/animations/Egypt/egypt.avif",
        staticImg: "casino-games/animations/Egypt/static-egypt.avif",
        lossToLoss: "casino-games/animations/Egypt/loss-to-loss-Egypt.avif",
        lossToWin: "casino-games/animations/Egypt/loss-to-win-Egypt.avif",
        winToLoss: "casino-games/animations/Egypt/win-to-loss-Egypt.avif",
        winToWin: "casino-games/animations/Egypt/win-to-win-Egypt.avif",
        categories: ["All"]
    ),
    CasinoGame(
        extId: "mystic-woods",
        name: "Mystic Woods",
        thumbnail: "casino-games/animations/Forest/wild_game_thumbnail.avif",
        staticImg: "casino-games/animations/Forest/static-forest.avif",
        lossToLoss: "casino-games/animations/Forest/loss-to-loss-forest.avif",
        lossToWin: "casino-games/animations/Forest/loss-to-win-forest.avif",
        winToLoss: "casino-games/animations/Forest/win-to-loss-forest.avif",
        winToWin: "casino-games/animations/Forest/win-to-win-forest.avif",
        categories: ["Top", "All"]
    ),
    CasinoGame(
        extId: "olympian-riches",
        name: "Olympian Riches",
        thumbnail: "casino-games/animations/Greek/greek.avif",
        staticImg: "casino-games/animations/Greek/static-greek.avif",
        lossToLoss: "casino-games/animations/Greek/loss-to-loss-greek.avif",
        lossToWin: "casino-games/animations/Greek/loss-to-win-greek.avif",
        winToLoss: "casino-games/animations/Greek/win-to-loss-greek.avif",
        winToWin: "casino-games/animations/Greek/win-to-win-greek.avif",
        categories: ["Top", "All"]
    ),
    CasinoGame(
        extId: "mystic-spin",
        name: "Mystic Spin",
        thumbnail: "casino-games/animations/India/india.avif",
        staticImg: "casino-games/animations/India/static-india.avif",
        lossToLoss: "casino-games/animations/India/loss-to-loss-india.avif",
        lossToWin: "casino-games/animations/India/loss-to-win-india.avif",
        winToLoss: "casino-games/animations/India/win-to-loss-india.avif",
        winToWin: "casino-games/animations/India/win-to-win-india.avif",
        categories: ["Top", "All"]
    ),
    CasinoGame(
        extId: "love-spin",
        name: "Love Spin",
        thumbnail: "casino-games/animations/st-valentines/valentines.avif",
        staticImg: "casino-games/animations/st-valentines/static_Valentines.avif",
        lossToLoss: "casino-games/animations/st-valentines/loss-to-loss-Valentines.avif",
        lossToWin: "casino-games/animations/st-valentines/loss-to-win-Valentines.avif",
        winToLoss: "casino-games/animations/st-valentines/win-to-loss-Valentines.avif",
        winToWin: "casino-games/animations/st-valentines/win-to-win-Valentines.avif",
        categories: ["All"]
    ),
    CasinoGame(
        extId: "luxe-spins",
        name: "Luxe Spins",
        thumbnail: "casino-games/animations/suits/suits_game_thumbnail.avif",
        staticImg: "casino-games/animations/suits/static-suits.avif",
        lossToLoss: "casino-games/animations/suits/loss-to-loss-suits.avif",
        lossToWin: "casino-games/animations/suits/loss-to-win-suits.avif",
        winToLoss: "casino-games/animations/suits/win-to-loss-suits.avif",
        winToWin: "casino-games/animations/suits/win-to-win-suits.avif",
        categories: ["Top", "All"]
    ),
    CasinoGame(
        extId: "viking-fortune",
        name: "Viking Fortune",
        thumbnail: "casino-games/animations/Viking/viking.avif",
        staticImg: "casino-games/animations/Viking/static-viking.avif",
        lossToLoss: "casino-games/animations/Viking/loss-to-loss-viking.avif",
        lossToWin: "casino-games/animations/Viking/loss-to-win-viking.avif",
        winToLoss: "casino-games/animations/Viking/win-to-loss-viking.avif",
        winToWin: "casino-games/animations/Viking/win-to-win-viking.avif",
        categories: ["Top", "All"]
    ),
    CasinoGame(
        extId: "witchs-spell",
        name: "Witchs Spell",
        thumbnail: "casino-games/animations/Witch/witch.avif",
        staticImg: "casino-games/animations/Witch/static-witch.avif",
        lossToLoss: "casino-games/animations/Witch/loss-to-loss-witch.avif",
        lossToWin: "casino-games/animations/Witch/loss-to-win-witch.avif",
        winToLoss: "casino-games/animations/Witch/win-to-loss-witch.avif",
        winToWin: "casino-games/animations/Witch/win-to-win-witch.avif",
        categories: ["Top", "All"]
    ),
]
