local winapi = require'winapi'
local shell = require'shell'
local xml2lua = require'xml2lua'
local inspect = require'inspect'
local handler = require("xmlhandler/tree")
local lanes = require'lanes'
local svn={}

function svn.islocked(path)
	local path = [[x:\do\GMod\metastruct\mapfiles\moon.vmf]]
	local ret,xml = shell.run{"svn",'status','-u','--xml',path}

	local parser = xml2lua.parser(handler)
	parser:parse(xml)

	return handler.root.status.target.entry["repos-status"].lock
end

svn.islocked()
os.exit(0)

function svn.lock() end
function svn.unlock() end
function svn.commit() end
function svn.update() end
return svn

