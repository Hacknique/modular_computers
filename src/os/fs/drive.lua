ctr.os.fs.drive = {}

DriveTypes = {
    HARD_DRIVE = [0, "hd", "hard_drive"],
    FLOPPY_DRIVE = [1, "fd", "floppy_drive"],
}

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

function ctr.os.fs.drive.create(id, pos, type)
    for key, value in pairs(DriveTypes) do
        if value[2] == type then
            local computer_meta = minetest.get_meta(pos)
            local n_filesystems = #mtfs.list_filesystems(pos)
            computer_meta:set_string("filesystem_".. .. tostring(n_filesystems + 1) .. "_" .. id, minetest.serialize({}))
        end
    end
    local computer_meta = minetest.get_meta(pos)
    local n_filesystems = #mtfs.list_filesystems(pos)
    computer_meta:set_string("filesystem_".. tostring(n_filesystems + 1) .. "_" .. id, minetest.serialize({}))
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

