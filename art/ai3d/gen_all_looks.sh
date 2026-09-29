#!/bin/zsh
cd ${0:A:h}
g() { zsh gen_look.sh "$1" "$2" 2>&1 | tail -1; }
g l06 "LA REINA: a regal Brazilian women's football legend, woman, deep brown skin, long thick box braids tied into a high ponytail, gold stud earrings, proud confident half-smile, athletic powerful build"
g l07 "BULLDOZER: an Ivorian power striker, man, very dark skin, clean shaved head, short full beard, massive broad shoulders and thick arms, towering and intimidating, calm predator stare"
g l08 "LA PULGA: a small, quiet Argentine genius, man, fair skin, short neat brown hair, full trimmed brown beard, compact short build, humble focused eyes, the smallest player on the pitch"
g l12 "THE WALL: a Dutch giant centre-back, man, light tan skin, dark hair in a tight man bun with shaved sides, neat beard, very tall and broad, commanding captain presence, arms relaxed"
g l09 "LE MAESTRO: an elegant French playmaker, man, olive skin, completely bald head, clean-shaven, lean graceful build, serene half-closed intense eyes, effortless calm aura"
g l10 "EL FENOMENO: a Brazilian goal machine, man, brown skin, head shaved except a small triangle tuft of hair at the front, big gap-toothed joyful grin, strong stocky powerful legs"
g l15 "FLASH: an explosive French speedster, man, dark brown skin, very short buzz cut, slim sprinter build with long legs, cocky smirk, lightning-quick energy"
g l11 "THE MACHINE: a Portuguese superstar winger, man, tanned skin, glossy slicked-back undercut with sharp fade, chiselled jaw and perfect eyebrows, very muscular athletic build, arrogant winner's smirk, huge ego aura"
g l14 "EGOIST: an anime prodigy striker, young woman, pale skin, sharp icy-white hair in a jagged bob with one long strand, piercing glowing ice-blue eyes, cold fearless stare, lean agile build"
echo ALLDONE
