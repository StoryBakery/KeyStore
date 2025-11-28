local KeyStore = require("../roblox_packages/KeyStore")

local keyStore = KeyStore.new()

local function isSame(a, b)
	if a ~= b then
		error(`Expected {a} to be {b}`, 2)
	end
end

task.spawn(function()
	isSame(keyStore:WaitForKeyPath({1,2,5,1}), 1251)
end)

wait(2)

keyStore:SetByKeyPath({1, 2, 5, 1}, 1251)


