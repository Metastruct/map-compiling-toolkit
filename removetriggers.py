import vmf_tool
import sys,os 

v = vmf_tool.Vmf(sys.argv[1])
outf=sys.argv[2]
#import code
#code.interact(local=locals())
removed=0
entities=v.raw_namespace.entities
for ent in entities:
	if ent.classname=="lua_trigger":
		#print(ent,ent.classname,ent.place)
		removed+=1
		entities.remove(ent)

print("Removed",removed,"triggers")

v.save_to_file(outf)