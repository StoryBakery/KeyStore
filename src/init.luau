local SharedTableRegistry = game:GetService("SharedTableRegistry")
local RunService = game:GetService("RunService")

local Signal = require("../roblox_packages/Signal")
local TableUtil = require("../roblox_packages/TableUtil")
local Promise = require("../roblox_packages/Promise")

local Package = script

local keyPathToString

local KeyStore = {}
KeyStore.__index = KeyStore
KeyStore.__type = "KeyStore"

--#region Constructors
type PathAdded<Item = any, Key = any> = 
	Signal.SignalBase<(key: Key, newChildPath: ItemPath)->(), any>

type ItemPath<Item = any, Key = any> = {
	Item: Item?,
	ItemAdded: Signal.ChangedSignal<Item>,

	Paths: { [Key]: ItemPath },
	PathAdded: PathAdded,
	ItemAndPathCount: number,


	IsRoot: boolean,
	WaitingConsumerCount: number
}

local createItemPath do

	function createItemPath(isRoot: boolean): ItemPath
		local itemPath: ItemPath = {
			ItemAdded = Signal.new(),

			Paths = {},
			PathAdded = Signal.new(),
			ItemAndPathCount = 0,

			IsRoot = isRoot,
			WaitingConsumerCount = 0,
		}

		return itemPath
	end
end

type RootItemPath<Item = any, Key = any> = {IsRoot: true} & ItemPath<Item, Key> 



export type KeyPath<Key = any> = {Key}

export type KeyStore<Item = any, Key = any> = setmetatable<{
	ItemPath: RootItemPath<Item, Key>,
	Name: string?,

	IsGlobal: boolean,
	IsShared: boolean,

	DefaultKeyType: string?,

	SetByKeyPath: (self: any, keyPath: KeyPath<Key>, item: Item, keyType: string?)->(),

	FindByKeyPath: (self: any, keyPath: KeyPath<Key>, keyType: string?) -> (Item?),

	GetByKeyPath: (self: any, keyPath: KeyPath<Key>, keyType: string?)->(Item),

	WaitForKeyPath: (self: any, keyPath: KeyPath<Key>, timeout: number?, keyType: string?)->(Item),

	RemoveByKeyPath: (self: any, keyPath: KeyPath<Key>, keyType: string?)->(),
}, typeof(KeyStore)>

local keyStoresByName = {} :: {[string]: KeyStore}

local DEFAULT_KEY_STORE_PARAMS = {
	Name = "Unknown",
	IsGlobal = false,
	IsShared = false,

	DefaultKeyType = nil :: string?,
}

type KeyStoreParams = typeof(DEFAULT_KEY_STORE_PARAMS)

function KeyStore.new<Item, Key>(params: KeyStoreParams?): KeyStore<Item, Key>
	local resolvedParams = TableUtil.merge(DEFAULT_KEY_STORE_PARAMS, params or {})

	local self = setmetatable({}, KeyStore)
	self.ItemPath = createItemPath(true)

	self.Name = resolvedParams.Name
	self.IsGlobal = resolvedParams.IsGlobal
	self.IsShared = resolvedParams.IsShared

	if self.IsGlobal then
		self:_insertToGlobalTable()
	end

	if self.IsShared then
		assert(self.IsGlobal, `A shared KeyStore must also be global.`)
		self:_insertToSharedTable()
	end

	self.DefaultKeyType = resolvedParams.DefaultKeyType

	return self
end

function KeyStore:_insertToGlobalTable()
	local name = self.Name

	if keyStoresByName[name] then
		error(`A KeyStore with the name "{name}" already exists.`)
	end
	keyStoresByName[name] = self
end

function KeyStore:_insertToSharedTable()
	error("Currently blocked API")
end

function KeyStore.GetOrCreate<Item, Key>(params: KeyStoreParams): KeyStore<Item, Key>
	return keyStoresByName[params.Name] or KeyStore.new(params)
end

--#region Functions
--[[
	Set Key Types
	
	To output id as a string for the user to identify easily.
	Keys are stored primarily as compressed strings to save memory or
	as tables for use as unique hash keys.
]]

local registeredKeyTypeInfosByName = {} :: {[string]: KeyTypeInfo}
local registeredKeyTypeNamesById = {} :: {[number]: string}

do
	local function findRegisteredKeyTypeInfo(keyType)
		local registeredKeyTypeInfo = registeredKeyTypeInfosByName[keyType]
		if registeredKeyTypeInfo then
			return registeredKeyTypeInfo
		end

		if coroutine.isyieldable() then
			local thread = coroutine.running()
			for i = 1, 5 do
				task.defer(function()
					registeredKeyTypeInfo = registeredKeyTypeInfosByName[keyType]
					task.spawn(thread)
				end)
				coroutine.yield()
				if registeredKeyTypeInfo then
					return registeredKeyTypeInfo
				end
			end
		end

		if not registeredKeyTypeInfo then
			warn(`No registered key type "{keyType}".`)
		end
	end

	function KeyStore.KeyPathToString(keyPath: KeyPath, keyType: string?): string
		if keyType then
			local registeredKeyTypeInfo = findRegisteredKeyTypeInfo(keyType)
			if registeredKeyTypeInfo then
				return registeredKeyTypeInfo.KeyPathToString(keyPath)
			end
		end

		local strings = {}
		for i, v in ipairs(keyPath) do
			strings[i] = if typeof(v) == "Instance" then v:GetFullName() else tostring(v)
		end
		return table.concat(strings, "|")
	end
end



keyPathToString = KeyStore.KeyPathToString


export type KeyTypeInfo = {
	Name: string,
	KeyPathToString: (any) -> (string),
	Id: number,
}

do
	local function getKeyPathToStringFromModuleObjectValue(moduleObjectValue: ObjectValue)
		local module = require(moduleObjectValue.Value)

		local keyPathToStringName = moduleObjectValue:GetAttribute("KeyPathToStringFunctionName")
		local func = module[keyPathToStringName]

		return func
	end

	local function registerKeyTypeFromModuleObjectValue(moduleObjectValue: ObjectValue)
		local name = moduleObjectValue.Name
		local keyPathToString = getKeyPathToStringFromModuleObjectValue(moduleObjectValue)
		local id = moduleObjectValue:GetAttribute("KeyTypeId")

		registeredKeyTypeInfosByName[name] = {
			Name = name,
			KeyPathToString = keyPathToString,
			Id = id,
		}
		registeredKeyTypeNamesById[id] = name
	end
end

--#tag RegisterKeyType
local DEFAULT_KEY_TYPE_PARAMS = {
	KeyPathToStringFunctionName = "KeyPathToString",

}

export type RegisterKeyTypeParams = typeof(DEFAULT_KEY_TYPE_PARAMS)

local highestId = 0
function KeyStore.RegisterKeyType(name: string, moduleScript: ModuleScript, params: RegisterKeyTypeParams?)
	local resolvedParams = TableUtil.merge(DEFAULT_KEY_TYPE_PARAMS, params or {})

	highestId += 1

	local keyPathToStringName = resolvedParams.KeyPathToStringFunctionName
	local func = require(moduleScript)[keyPathToStringName]


	registeredKeyTypeInfosByName[name] = {
		Name = name,
		KeyPathToString = func,
		Id = highestId
	}
	registeredKeyTypeNamesById[highestId] = registeredKeyTypeInfosByName[name]
end

--#tag UnregisterKeyType
function KeyStore.UnregisterKeyType(name: string, moduleScript: ModuleScript, toStringFunctionName: string?)
	local existing = registeredKeyTypeInfosByName[name]
	if existing then
		registeredKeyTypeInfosByName[name] = nil
		registeredKeyTypeNamesById[existing.Id] = nil
	end
end

--#tag FindKeyTypeInfo
function KeyStore.FindKeyTypeInfo(keyType: string): KeyTypeInfo?
	return registeredKeyTypeInfosByName[keyType]
end

--#tag GetKeyTypeInfo
function KeyStore.GetKeyTypeInfo(keyType: string): KeyTypeInfo
	local keyTypeInfo = KeyStore.FindKeyTypeInfo(keyType)
	return if keyTypeInfo then keyTypeInfo else error(`Key "{keyType}" isn't registered.`)
end

--#tag GetKeyTypeFromId
function KeyStore.GetKeyTypeFromId(id: number): string
	local keyType = registeredKeyTypeNamesById[id]
	return keyType or error(`Key with ID "{id}" isn't registered.`)
end

--#tag IsKeyTypeRegistered
function KeyStore.IsKeyTypeRegistered(keyType: string): boolean
	return registeredKeyTypeInfosByName[keyType] ~= nil
end

--#region Methods

function KeyStore:__tostring(): string
	return `KeyStore {self.Name}`
end

--[[
	Use array to attach Key to property of an instance or tree list.
	Key "{instance, propertyName}" will save as 
	"itemsByKey[instance].Paths[propertyName].Item = item"
]]
function KeyStore:SetByKeyPath(keyPath: KeyPath, item: any, keyType: string?)
	local self: KeyStore = self
	local length = #keyPath
	assert(length ~= 0, `KeyPath is Non-Array or 0 Length.`)

	local currentPath = self.ItemPath :: ItemPath

	for i = 1, length do
		local key = keyPath[i]
		local childPath = currentPath.Paths[key]
		if not childPath then
			childPath = createItemPath(false)

			currentPath.ItemAndPathCount += 1
			currentPath.Paths[key] = childPath
			currentPath.PathAdded:Fire(key, childPath)

			currentPath = childPath
		end

		currentPath = childPath
	end

	local existingItem = currentPath.Item
	if existingItem ~= nil then
		local key = KeyStore.KeyPathToString(keyPath, keyType)
		error(`Key "{key}" is already set as "{existingItem}".`, 2)
	end

	currentPath.Item = item
	currentPath.ItemAndPathCount += 1
	currentPath.ItemAdded:Fire(item)
end

function KeyStore:FindByKeyPath(
	keyPath: KeyPath, 
	keyType: string?,
	onMissing: ((currentPath: ItemPath, key: any, childPath: ItemPath?, index: number)->(boolean?))?
): any?
	local currentPath = self.ItemPath :: ItemPath

	local length = #keyPath
	if length == 0 then
		error(
			`KeyPath "{KeyStore.KeyPathToString(keyPath, self.DefaultKeyType)}" is Non-Array or 0 Length.`
		)
	end

	for i = 1, length do
		local key = keyPath[i]
		local childPath = currentPath.Paths[key]
		if not childPath or childPath.ItemAndPathCount == 0 then 
			if not onMissing then
				return nil
			end

			local shouldContinue = onMissing(currentPath, key, childPath, i)

			if shouldContinue then
				childPath = currentPath.Paths[key]

				if not childPath then
					return nil
				end
			else
				return nil
			end
		end

		currentPath = childPath
	end

	return currentPath.Item
end

function KeyStore:_errorOnFailedToFind(
	missingKey: any, 
	index: number, 
	keyPath: KeyPath, 
	keyType: string?, 
	level: number?
)

	error(
		`Cannot find the item with the specified Key: `..
			`"{keyPathToString(keyPath, keyType)}" `..
			`from {index}th Key "{missingKey}".`,
		level
	)
end

function KeyStore:GetByKeyPath(keyPath: KeyPath, keyType: string?): any
	return self:FindByKeyPath(keyPath, keyType, function(
		currentPath, 
		key, 
		childPath,
		index
	)
		self:_errorOnFailedToFind(key, index, keyPath, keyType or self.KeyType, 3)
	end)
end

local function shouldRemoveItemPath(itemPath: ItemPath): boolean
	if 
		itemPath.IsRoot 
		or itemPath.ItemAndPathCount > 0
		or itemPath.WaitingConsumerCount > 0
	then
		return false
	end

	for _, childPath in itemPath.Paths do
		if not shouldRemoveItemPath(childPath) then
			return false
		end
	end

	return true
end

function KeyStore:_waitForKeyPathNoTimeout(keyPath: KeyPath)
	return Promise.new(function(resolve, reject, onCancel)
		local currentThread = coroutine.running()

		local parentPath: ItemPath
		local currentPath = self.ItemPath :: ItemPath
		local currentKey

		onCancel(function()
			if coroutine.status(currentThread) == "dead" then
				return
			end

			task.cancel(currentThread)
			currentPath.WaitingConsumerCount -= 1

			if shouldRemoveItemPath(currentPath) then
				parentPath[currentKey] = nil
			end
		end)

		for i = 1, #keyPath do
			currentKey = keyPath[i]
			local childPath = currentPath.Paths[currentKey]

			if childPath == nil then
				currentPath.WaitingConsumerCount += 1

				local _, newChildPath = Promise.fromEvent(
					currentPath.PathAdded, function(newKey, newChildPath)
						return newKey == currentKey
					end
				):andThen(function(newKey, newChildPath)
					return newChildPath
				end):await()

				childPath = newChildPath

				currentPath.WaitingConsumerCount -= 1
			end

			parentPath = currentPath
			currentPath = childPath
		end

		local item = currentPath.Item

		if item == nil then
			currentPath.WaitingConsumerCount += 1
			item = currentPath.ItemAdded:Wait()
			currentPath.WaitingConsumerCount -= 1
		end

		resolve(item)
	end)
end

function KeyStore:WaitForKeyPath(keyPath: KeyPath, timeout: number?, keyType: string?): any
	local self: KeyStore = self

	local item = self:FindByKeyPath(keyPath, keyType)
	if item ~= nil then
		return item
	end

	local suc, item
	if timeout then
		suc, item = self:_waitForKeyPathNoTimeout(keyPath):timeout(timeout):await()
	else
		suc, item = self:_waitForKeyPathNoTimeout(keyPath):await()
	end

	if suc then
		return item
	else
		return nil
	end
end

do
	local function removeNeedlessPathsFromDescendantToRoot(
		pathsFromRootToDescendant: {ItemPath}, 
		keyPath: KeyPath,
		length: number?
	)
		local length = length or #pathsFromRootToDescendant
		local changedChildPath = pathsFromRootToDescendant[length]

		for i = length + 1, 2, -1 do
			if not shouldRemoveItemPath(changedChildPath) then
				return
			end

			local parentPath = pathsFromRootToDescendant[i-1]
			parentPath.ItemAndPathCount -= 1

			local parentKey = keyPath[i-1]
			parentPath.Paths[parentKey] = nil

			changedChildPath = parentPath
		end
	end

	function KeyStore:_getPathsFromRootToGoal(keyPath: KeyPath, length: number?, keyType: string?): {ItemPath}
		local currentPath = self.ItemPath :: ItemPath
		local length = length or #keyPath

		local paths = {currentPath}

		for i = 1, length do
			local childKey = keyPath[i]
			local childPath = currentPath.Paths[childKey]

			if childPath == nil then
				self:_errorOnFailedToFind(childKey, i, keyPath, keyType or self.KeyType, 3)
			end

			currentPath = childPath
			table.insert(paths, currentPath)
		end

		return paths
	end

	function KeyStore:RemoveByKeyPath(keyPath: KeyPath, keyType: string?)

		local length = #keyPath
		assert(length ~= 0, `KeyPath is Non-Array or 0 Length.`)

		local paths = self:_getPathsFromRootToGoal(keyPath, length, keyType)
		local goalPath = paths[length + 1]

		local item = goalPath.Item
		if item == nil then
			self:_errorOnFailedToFind(keyPath[length], length, keyPath, keyType)
		end

		goalPath.Item = nil
		goalPath.ItemAndPathCount -= 1

		removeNeedlessPathsFromDescendantToRoot(paths, keyPath, length)
	end
end



do
	local function getPaths(itemPath: ItemPath, keyPaths: {any}, lastKeyPath: {any})
		for key, childItemPath in itemPath.Paths do
			local currentKeyPath = table.clone(lastKeyPath)
			table.insert(currentKeyPath, key)

			if childItemPath.Item ~= nil then
				table.insert(keyPaths, currentKeyPath)
			end

			if childItemPath.ItemAndPathCount > 0 then
				getPaths(childItemPath, keyPaths, currentKeyPath)
			end
		end
	end

	function KeyStore:GetKeyPaths(): {KeyPath}
		local keyPaths = {}
		getPaths(self.ItemPath, keyPaths, {})

		return keyPaths
	end
end

function KeyStore:Reset()
	local self: KeyStore = self

	local keyPaths = self:GetKeyPaths()

	for i, keyPath in keyPaths do
		self:RemoveByKeyPath(keyPath)
	end
end

export type KeyStoreModule = typeof(KeyStore)

return KeyStore
