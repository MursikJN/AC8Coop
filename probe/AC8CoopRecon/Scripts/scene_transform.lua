local M={}
function M.multiply(a,b)
 local x,y,z,w=table.unpack(a);local X,Y,Z,W=table.unpack(b)
 return {w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z}
end
function M.inverse(q)return{-q[1],-q[2],-q[3],q[4]}end
function M.rotate(q,p)
 local r=M.multiply(M.multiply(q,{p[1],p[2],p[3],0}),M.inverse(q));return{r[1],r[2],r[3]}
end
function M.relative(parent,p,q)
 local delta={};for i=1,3 do delta[i]=p[i]-parent.position[i]end
 return M.rotate(M.inverse(parent.rotation),delta),M.multiply(M.inverse(parent.rotation),q)
end
function M.world(parent,part)
 local p=M.rotate(parent.rotation,part.position);for i=1,3 do p[i]=p[i]+parent.position[i]end
 return p,M.multiply(parent.rotation,part.rotation)
end
return M
