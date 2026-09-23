require("mineunit")

mineunit("core")
mineunit("server")
sourcefile("init")

describe("internet card", function()

	local internet = modular_computers.internet
	mineunit:mods_loaded()

	it("is off unless the server allows it", function()
		assert.is_false(internet.is_enabled())
	end)

	it("allows web addresses", function()
		for _, url in ipairs({ "https://example.com/", "http://example.com:8080/a?b=c", "https://user@example.org/x",
			"https://8.8.8.8/", "HTTP://EXAMPLE.COM" }) do
			assert.is_true(internet.check_url(url), url)
		end
	end)

	it("refuses the server and local networks", function()
		for _, url in ipairs({ "http://localhost/", "http://LOCALHOST.:8080/", "http://127.0.0.1/", "http://127.1/",
			"http://2130706433/", "http://0x7f000001/", "http://0177.0.0.1/", "http://10.1.2.3/", "http://192.168.0.1/",
			"http://172.16.5.5/", "http://169.254.169.254/latest/meta-data", "http://[::1]/", "http://0.0.0.0/",
			"http://printer.local/", "http://db.internal/", "http://example.com@127.0.0.1/" }) do
			assert.is_nil(internet.check_url(url), url)
		end
	end)

	it("refuses other protocols and broken addresses", function()
		for _, url in ipairs({ "file:///etc/passwd", "ftp://example.com/", "gopher://example.com/", "example.com",
			"http://exa mple.com/", "http://example.com/\n" }) do
			assert.is_nil(internet.check_url(url), url)
		end
	end)

end)
