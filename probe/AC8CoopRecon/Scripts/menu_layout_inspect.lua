return function(output,stamp)
 local f=assert(io.open(output..'/menu-layout-'..stamp..'.tsv','w'))
 local function row(...)local t={...};for i,v in ipairs(t)do t[i]=tostring(v):gsub('[\r\n\t]',' ')end;f:write(table.concat(t,'\t'),'\n');f:flush()end
 local function walk(o,depth)
  if not o or not o:IsValid()or depth>24 then return end
  local n=o:GetFullName();row('widget',n,o.Visibility)
  local slot=o.Slot
  if slot and slot:IsValid()then
   row('slot',n,slot:GetFullName())
   for _,k in ipairs({'Row','Column','RowSpan','ColumnSpan','HorizontalAlignment','VerticalAlignment'})do pcall(function()row('slot_value',n,k,slot[k])end)end
  end
  if o:IsA('/Script/UMG.TextBlock')then
   row('text',n,o:GetText():ToString(),'font_size',o.Font.Size)
  elseif o:IsA('/Script/UMG.UserWidget')then walk(o.WidgetTree.RootWidget,depth+1)
  elseif o:IsA('/Script/UMG.PanelWidget')then for i=0,math.min(o:GetChildrenCount(),32)-1 do walk(o:GetChildAt(i),depth+1)end end
 end
 for _,main in ipairs(FindAllOf('LiveMenuMainTopWidget')or{})do
  if main:IsValid()and not main:GetFullName():find('Default__',1,true)then
   walk(main.CommandList,0)
   for _,key in ipairs({'Menu_01','Menu_06','ListVerticalParentBox','ListHorizontalParentBox','ListWrapParentBox'})do
    pcall(function()local o=main.CommandList[key];row('reference',key,o:IsValid()and o:GetFullName()or'invalid')end)
   end
  end
 end
 for _,path in ipairs({'/Script/UMG.GridPanel','/Script/UMG.GridSlot','/Script/UMG.CanvasPanel','/Script/UMG.CanvasPanelSlot'})do
  local c=StaticFindObject(path)
  c:ForEachFunction(function(fn)
   local n=fn:GetFName():ToString();row('function',path,n)
   fn:ForEachProperty(function(p)row('parameter',path,n,p:GetFName():ToString(),p:GetClass():GetFName():ToString())end)
  end)
 end
 f:close()
end
