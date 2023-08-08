import GameServer.AbstractCtx
import GameServer.Graph



/-- The default game name if `Game "MyGame"` is not used. -/
def defaultGameName: String := "MyGame"
-- Note: When changing any of these default names, one also needs to change them in `index.mjs`

/-- The default game module name. -/
def defaultGameModule: String := "Game"

/-! # Environment extensions

The game framework stores almost all its game building data in environment extensions
defined in this file.
-/

open Lean

/-! ## Hints -/

/-- A hint to help the user with a specific goal state -/
structure GoalHintEntry where
  goal : AbstractCtxResult
  /-- Text of the hint as an expression of type `Array Expr → MessageData` -/
  text : Expr
  /-- If true, then hint should be hidden and only be shown on player's request -/
  hidden : Bool := false
  /-- If true, then the goal must contain only the assumptions specified in `goal` and no others -/
  strict : Bool := false

instance : Repr GoalHintEntry := {
  reprPrec := fun a n => reprPrec a.text n
}

/-! ## Inventory (documentation)

The inventory contains documentation that the user can access.
There are three inventory types: Lemma, Tactic, Definition. They vary about in the information
they carry.

The commands `LemmaDoc`, `TacticDoc`, and `DefinitionDoc` add keys and templates to an
env. extension called `InventoryTemplateExt`. Commands like `NewLemma`, etc. as well as
`Statement` check if there is a key registered in this extension and might add a default or
print a warning if not.

Then, `MakeGame` takes the templates from `InventoryTemplateExt` and creates the documentation entries
that are sent to the client. This allows us to modify them like adding information from
mathlib or from parsing the lemma in question.
-/

/-- The game knows three different inventory types that contain slightly different information -/
inductive InventoryType := | Tactic | Lemma | Definition
deriving ToJson, FromJson, Repr, BEq, Hashable, Inhabited

-- TODO: golf this?
instance : ToString InventoryType := ⟨fun t => match t with
| .Tactic => "Tactic"
| .Lemma => "Lemma"
| .Definition => "Definition"⟩

/-- The keys/templates of the inventory items, stored in `InventoryTemplateExt`. -/
structure InventoryTemplate where
  /-- Lemma, Tactic, or Definition -/
  type: InventoryType
  /-- Depends on the type:
  * Tactic: the tactic's name
  * Lemma: fully qualified lemma name
  * Definition: no restrictions (preferrably the definions fully qualified name)
  -/
  name: Name
  /-- Only for Lemmas. To sort them into tabs -/
  category: String := default
  /-- Free-text short name -/
  displayName: String := name.toString
  /-- Template documentation. Allows for special tags to insert mathlib info [TODO!] -/
  content: String := ""
  deriving ToJson, Repr, Inhabited

/-- A full inventory item including the processing by `MakeGame`, which creates these
from the `InventoryTemplate`s and modifies them. -/
structure InventoryItem extends InventoryTemplate where
  statement: String := ""
  deriving ToJson, Repr, Inhabited

/-- A reduced variant of `InventoryItem` which is used for the tiles in the doc -/
structure InventoryTile where
  /--
  The name of the item. The restrictions are:

  * for Tactics: The name of the tactic.
  * for Lemmas: *Fully qualified* lemma name.
  * for Definitions: no restrictions.
  -/
  name : Name
  /-- The display name shown in the inventory. This can be free-text. -/
  displayName : String
  /-- Category to group inventory items by (currently only used for lemmas). -/
  category : String
  /-- If `true` then the item only gets unlocked in a later level. -/
  locked := true
  /-- If `true` then the item is blocked for this level. -/
  disabled := false
  /-- To mark an item that has been added freshly in this level. -/
  new := false
deriving ToJson, FromJson, Repr, Inhabited

/-- The extension that stores the doc templates. Note that you can only add, but never modify
entries! -/
initialize inventoryTemplateExt :
    SimplePersistentEnvExtension InventoryTemplate (Array InventoryTemplate) ←
  registerSimplePersistentEnvExtension {
    name := `inventory_keys
    addEntryFn := Array.push
    addImportedFn := Array.concatMap id }

/-- Receive the template with that matches `(name, type)` -/
def getInventoryTemplate? [Monad m] [MonadEnv m] (n : Name) (type : InventoryType) :
    m (Option InventoryTemplate) := do
  return (inventoryTemplateExt.getState (← getEnv)).find? (fun x => x.name == n && x.type == type)

/-- The extension that contains the inventory content after it has been processed.
`MakeGame` is the only command adding items here. -/
initialize inventoryExt : SimplePersistentEnvExtension InventoryItem (Array InventoryItem) ←
  registerSimplePersistentEnvExtension {
    name := `inventory_doc
    addEntryFn := Array.push
    addImportedFn := Array.concatMap id }

/-- Receive the item with that matches `(name, type)` -/
def getInventoryItem? [Monad m] [MonadEnv m] (n : Name) (type : InventoryType) :
    m (Option InventoryItem) := do
  return (inventoryExt.getState (← getEnv)).find? (fun x => x.name == n && x.type == type)



/-! ## Environment extensions for game specification -/

/-- Register a (non-persistent) environment extension to hold the current level -/
initialize curGameExt : EnvExtension (Option Name) ← registerEnvExtension (pure none)
/-- Register a (non-persistent) environment extension to hold the current level -/
initialize curWorldExt : EnvExtension (Option Name) ← registerEnvExtension (pure none)
/-- Register a (non-persistent) environment extension to hold the current level -/
initialize curLevelExt : EnvExtension (Option Nat) ← registerEnvExtension (pure none)

/--
A game has three layers: Game, World, Levels. These are set with the commands
`Game`, `World`, and `Level`. Commands like `Introduction` depend on the current level.
-/
inductive Layer :=
| Game | World | Level

variable {m: Type → Type} [Monad m] [MonadEnv m]

/-- Set the current game -/
def setCurGameId (game : Name) : m Unit :=
  modifyEnv (curGameExt.setState · game)

/-- Set the current world -/
def setCurWorldId (world : Name) : m Unit :=
  modifyEnv (curWorldExt.setState · world)

/-- Set the current level -/
def setCurLevelIdx (level : Nat) : m Unit :=
  modifyEnv (curLevelExt.setState · level)

/-- Get the current layer. -/
def getCurLayer [MonadError m] : m Layer := do
  -- previously, we also had `curGameExt.getState (← getEnv), ` in here, which got removed
  -- when we made the `Game` command optional
  match curWorldExt.getState (← getEnv), curLevelExt.getState (← getEnv) with
  | some _, some _ => return Layer.Level
  | some _, none => return Layer.World
  | none, none => return Layer.Game
  | _, _ => throwError "Invalid Layer"

/-- Get the current game, or default if none is specified -/
def getCurGameId [Monad m] : m Name := do
  match curGameExt.getState (← getEnv) with
  | some game => return game
  | none => return defaultGameName

/-- Get the current world -/
def getCurWorldId [MonadError m] : m Name := do
  match curWorldExt.getState (← getEnv) with
  | some world => return world
  | none => throwError "Current world not set"

/-- Get the current level -/
def getCurLevelIdx [MonadError m] : m Nat := do
  match curLevelExt.getState (← getEnv) with
  | some level => return level
  | none => throwError "Current level not set"

/-! ## Levels -/

structure LevelId where
  game : Name
  world : Name
  level : Nat
deriving Inhabited

structure InventoryInfo where
  /-- new inventory items introduced by this level -/
  new : Array Name
  /-- inventory items exceptionally forbidden in this level -/
  disabled : Array Name
  /-- only these inventory items are allowed in this level (ignored if empty) -/
  only : Array Name
  /-- inventory items in this level (computed by `MakeGame`) -/
  tiles : Array InventoryTile
deriving ToJson, FromJson, Repr, Inhabited

def getCurLevelId [MonadError m] : m LevelId := do
  return { game := ← getCurGameId, world := ← getCurWorldId, level := ← getCurLevelIdx}

/-- Instance to make GameLevel Repr work -/
instance : Repr Elab.Command.Scope := ⟨fun s _ => repr s.currNamespace⟩

structure GameLevel where
  index: Nat
  /-- The title of the level. -/
  title: String := default
  /-- Introduction text shown all the time. (markdown) -/
  introduction: String := default
  conclusion: String := default
  /-- The name of the exercise proven. If provided this lemma will be available in
  future levels. -/
  statementName: Name := default
  hints: Array GoalHintEntry := default
  /-- The statement in Lean. -/
  goal : TSyntax `Lean.Parser.Command.declSig := default
  scope : Elab.Command.Scope := default
  /-- The mathematical statement in mathematician-readable form. (markdown) -/
  descrText: Option String := none
  descrFormat : String := default
  /-- The `category` of lemmas to be open by default -/
  lemmaTab: Option String := none
  /-- The module to be imported when playing this level -/
  module : Name := default
  tactics: InventoryInfo := default
  definitions: InventoryInfo := default
  lemmas: InventoryInfo := default
  deriving Inhabited, Repr


/-! ## World -/

/-- A world is a collection of levels, like a chapter. -/
structure World where
  /- Internal name of the world. Not visible to the player. -/
  name: Name
  /-- Display title of the world. -/
  title: String := default
  /-- World introduction to be shown before the first level is loaded. (markdown) -/
  introduction: String := default
  /-- TODO: This is currently unused. -/
  conclusion : String := default
  /-- The levels of the world. -/
  levels: HashMap Nat GameLevel := default
deriving Inhabited

instance : ToJson World := ⟨
  fun world => Json.mkObj [
    ("name", toJson world.name),
    ("title", world.title),
    ("introduction", world.introduction)]
⟩

/-! ## Game -/

structure Game where
  /-- Internal name of the game. -/
  name : Name
  /-- TODO: currently unused. -/
  title : String := default
  /-- Text displayed on the main landing page of the game. -/
  introduction : String := default
  /-- TODO: currently unused. -/
  conclusion : String := default
  /-- TODO: currently unused. -/
  authors : List String := default
  worlds : Graph Name World := default
deriving Inhabited, ToJson

/-! ## Game environment extension -/

def HashMap.merge [BEq α] [Hashable α] (old : HashMap α β) (new : HashMap α β) (merge : β → β → β) :
  HashMap α β :=
new.fold (fun acc a b =>
  if let some bOld := acc.find? a
  then acc.insert a (merge bOld b)
  else acc.insert a b) old

def GameLevel.merge (old : GameLevel) (new : GameLevel) : GameLevel :=
  new -- simply override old level

def World.merge (old : World) (new : World) : World :=
{ new with
  levels := HashMap.merge old.levels new.levels GameLevel.merge}

def Game.merge (old : Game) (new : Game) : Game :=
{ new with
  worlds := {
    nodes := HashMap.merge old.worlds.nodes new.worlds.nodes World.merge
    edges := Id.run do
      let mut res := old.worlds.edges
      for e in new.worlds.edges do
        if ¬ res.contains e then
          res := res.push e
      return res
  } }

initialize gameExt : PersistentEnvExtension (Name × Game) (Name × Game) (HashMap Name Game) ←
  do registerPersistentEnvExtension {
    name          := `gameExt,
    mkInitial     := pure {},
    addImportedFn := fun ess => do
      let mut games := {}
      for es in ess do
        for (name, game) in es do
          match games.find? name with
          | some oldgame =>
            games := games.insert name (Game.merge oldgame game)
          | none =>
            games := games.insert name game
      return games
    addEntryFn    := (λ s n => s.insert n.1 n.2),
    exportEntriesFn := HashMap.toArray,
    statsFn := fun s => format "number of local entries: " ++ format s.size
}

def getGame? (n : Name) : m (Option Game) := do
  return (gameExt.getState (← getEnv)).find? n

def insertGame (n : Name) (g : Game) : m Unit := do
  modifyEnv (gameExt.addEntry · (n, g))

def getLevel? (levelId : LevelId) : m (Option GameLevel) := do
  let some game ← getGame? levelId.game
    | return none
  let some world := game.worlds.nodes.find? levelId.world
    | return none
  let some level := world.levels.find? levelId.level
    | return none
  return level

def getCurGame [Monad m] : m Game := do
  let some game ← getGame? (← getCurGameId)
    | let game := {name := defaultGameName}
      insertGame defaultGameName game
      return game
  return game

def modifyCurGame (fn : Game → m Game) [MonadError m] : m Unit := do
  let game ← getCurGame
  insertGame game.name (← fn game)

def addWorld (world : World) [MonadError m] : m Unit := do
  modifyCurGame fun game => do
    return {game with worlds := game.worlds.insertNode world.name world}

def getCurWorld [MonadError m] : m World := do
  let some world := (← getCurGame).worlds.nodes.find? (← getCurWorldId)
    | throwError m!"World {← getCurWorldId} does not exist"
  return world

def modifyCurWorld (fn : World → m World) [MonadError m] : m Unit := do
  modifyCurGame fun game => do
    let world ← getCurWorld
    return {game with worlds := {game.worlds with nodes := game.worlds.nodes.insert world.name (← fn world) }}

def addLevel (level : GameLevel) [MonadError m] : m Unit := do
  modifyCurWorld fun world => do
    return {world with levels := world.levels.insert level.index level}

def getCurLevel [MonadError m] : m GameLevel := do
  let some level := (← getCurWorld).levels.find? (← getCurLevelIdx)
    | throwError m!"Level {← getCurLevelIdx} does not exist"
  return level

def modifyCurLevel (fn : GameLevel → m GameLevel) [MonadError m] : m Unit := do
  modifyCurWorld fun world => do
    let level ← getCurLevel
    return {world with levels := world.levels.insert level.index (← fn level)}

def modifyLevel (levelId : LevelId) (fn : GameLevel → m GameLevel) [MonadError m] : m Unit := do
  let some game ← getGame? levelId.game
    | throwError m!"Game {levelId.game} does not exist"
  let some world := (← getCurGame).worlds.nodes.find? levelId.world
    | throwError m!"World {levelId.world} does not exist"
  let some level := world.levels.find? levelId.level
    | throwError m!"Level {levelId.level} does not exist"
  let level' ← fn level
  let world' := {world with levels := world.levels.insert levelId.level level'}
  let game' := {game with worlds := game.worlds.insertNode levelId.world world'}
  insertGame levelId.game game'
