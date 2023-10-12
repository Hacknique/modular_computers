ctr.os.fs.drive = {}

DriveTypes = {"hd", "fd"}
-- 1 -> HDD
-- 2 -> FDD

DRIVE_LETTERS = {
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z"
}

function ctr.os.fs.drive.create(pos, type_id)
    for index in ipairs(DriveTypes) do
        if index == type_id then
            local computer_meta = minetest.get_meta(pos)
            local n_filesystems = #ctr.os.fs.drive.list(pos)

            computer_meta:set_string("drive_".. DriveTypes[index] .. DRIVE_LETTERS[n_filesystems + 1], minetest.serialize({}))
        end
    end
end

function ctr.os.fs.drive.get(pos)
    local computer_meta = minetest.get_meta(pos)
    local filesystem = computer_meta:get_string("filesystem")
    return minetest.deserialize(filesystem)
end

function ctr.os.fs.drive.list(pos)
    local computer_meta = minetest.get_meta(pos)
    local filesystems = {}
    for key, value in pairs(computer_meta:to_table().fields) do
        if string.find(key, "filesystem_") then
            table.insert(filesystems, key)
        end
    end
    return filesystems
end

