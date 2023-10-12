function ctr.generate_id(player_name)
    local current_time = tostring(os.time())
    return minetest.get_password_hash(player_name, current_time)
end