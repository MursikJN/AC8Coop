-- Exact Russian captions captured from the stock difficulty widget, build
-- 25201480. Wire value 1 remains Easy (stock caption ПИЛОТ); do not renumber
-- existing sessions when presenting the stock order. Value 4 is the novice
-- choice; it is not the nonexistent "Ас" label used by the old local UI.
return {
 difficulties={
  {value=4,stock_index=0,caption='НОВИЧОК (СЮЖЕТ)'},
  {value=1,stock_index=1,caption='ПИЛОТ'},
  {value=2,stock_index=2,caption='ВЕТЕРАН'},
  {value=3,stock_index=3,caption='ЭЛИТА'},
 },
 missions={{value=6,caption='ЗАДАНИЕ 6'}},
}
