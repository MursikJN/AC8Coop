-- Read-only reflection inventory. Deliberately does not call any game function.
return function(output,id)
 local f=assert(io.open(output..'/sync-schema-'..id..'.tsv','w'));local count=0
 local classes={}
 for _,name in ipairs({'LiveCinematicsBlueprintFunctionLibrary','LiveCinematicsCinemaPlayer','LiveCinematicsSubsystem','LiveCinematicsWorldSubsystem','LiveCinematicsTop','LiveCinematicsPlayableStateManager','LiveCinematicsPlayableStateData','LiveCinematicsSequenceOptions','LiveCinematicsSequencePlaybackSettings','LiveCinematicsSkipPauseSubsystem','LiveSkipOperationAbstractStrategy','LiveSkipOperationManager','LiveSkipOperationPressHoldSkipStrategy','LiveSkipOperationPressHoldSkipUnGuideStrategy','LiveCinematicsLevelSequencePlayer','LiveCinematicsLevelSequencePlayerPlayingState','LiveCinematicsSkipWidget','LiveMovieViewer','LiveManaMovieViewer','LiveMenuMovieTransitionWidget','LiveUISkipConfig','LiveUIMovieGameplayStatics','MovieSceneSequencePlayer','GameplayStatics'})do
  for _,module in ipairs({'Live','LiveCinematics','MovieScene','Engine'})do
   local class=StaticFindObject('/Script/'..module..'.'..name);if class and class:IsValid()then classes[#classes+1]=class end
  end
 end
 for _,class in ipairs(classes)do
  if class:IsValid()then
   local name=class:GetFullName();local lower=name:lower()
   if true then
    count=count+1;assert(count<=256,'Class inventory cap')
    f:write('class\t',name,'\n')
    class:ForEachProperty(function(p)f:write('property\t',name,'\t',p:GetFName():ToString(),'\t',p:GetClass():GetFName():ToString(),'\n')end)
    class:ForEachFunction(function(fn)
     f:write('function\t',fn:GetFullName(),'\t',fn:GetFunctionFlags(),'\n')
     fn:ForEachProperty(function(p)f:write('argument\t',fn:GetFullName(),'\t',p:GetFName():ToString(),'\t',p:GetClass():GetFName():ToString(),'\n')end)
    end)
   end
  end
 end
 f:write('count\t',count,'\n');f:close()
end
