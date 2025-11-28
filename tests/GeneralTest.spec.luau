local KeyStore = require("../roblox_packages/KeyStore")

local keyStore = KeyStore.new()

local function isSame(a, b)
	if a ~= b then
		error(`Expected {a} to be {b}`, 2)
	end
end

keyStore:SetByKeyPath({1}, 1)
keyStore:SetByKeyPath({1, 2}, 12)
keyStore:SetByKeyPath({1, 2, 3}, 123)
keyStore:SetByKeyPath({1, 2, 4}, 124)
keyStore:SetByKeyPath({1, 2, 5}, 125)
keyStore:SetByKeyPath({1, 2, 5, 1}, 1251)

keyStore:SetByKeyPath({2}, 2)
keyStore:SetByKeyPath({3}, 3)
keyStore:SetByKeyPath({4}, 4)

isSame(keyStore:GetByKeyPath({1}), 1 )
isSame(keyStore:GetByKeyPath({1, 2}), 12 )
isSame(keyStore:GetByKeyPath({1, 2, 3}), 123 )
isSame(keyStore:GetByKeyPath({1, 2, 4}), 124 )
isSame(keyStore:GetByKeyPath({1, 2, 5}), 125 )
isSame(keyStore:GetByKeyPath({1, 2, 5, 1}), 1251 )

isSame(keyStore:GetByKeyPath({2}), 2)
isSame(keyStore:GetByKeyPath({3}), 3)
isSame(keyStore:GetByKeyPath({4}), 4)

isSame(keyStore:FindByKeyPath({1,2,5}), 125)
isSame(keyStore:FindByKeyPath({1,2,5,1}), 1251)
isSame(keyStore:FindByKeyPath({1,2,5,2}), nil)


task.spawn(function()
	isSame(keyStore:WaitForKeyPath({1,2,3}, 5), 123)
	isSame(keyStore:WaitForKeyPath({1,2,3,4}, 5), 1234)
end)

wait(1)

keyStore:SetByKeyPath({1,2,3,4}, 1234)

task.spawn(function()
	isSame(keyStore:WaitForKeyPath({1,2,3,4,1}, 5), 12341)
end)

print(#keyStore:GetKeyPaths())

wait(1)

keyStore:RemoveByKeyPath({1,2,3})

wait(1)

print(#keyStore:GetKeyPaths())

print(keyStore.ItemPath)

wait(1)

isSame(keyStore:FindByKeyPath({1,2,3}), nil)
isSame(keyStore:FindByKeyPath({1,2,3,4}), 1234)

keyStore:SetByKeyPath({1,2,3,4,1}, 12341)
isSame(keyStore:FindByKeyPath({1,2,3}), nil)
isSame(keyStore:FindByKeyPath({1,2,3,4,1}), 12341)

wait(1)

task.spawn(function()
	isSame(keyStore:WaitForKeyPath({1,2,3}, 1), nil)
end)

wait(2)

keyStore:Reset()

print(keyStore:GetKeyPaths())

print(keyStore.ItemPath)

isSame(#keyStore:GetKeyPaths(), 0)
