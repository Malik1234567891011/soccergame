#!/bin/zsh
# Roster v2 sheets: legends with close likenesses, new stars, and fantasy characters.
cd ${0:A:h}
typeset -A D
D[l04]="anime likeness of Ronaldinho: Brazilian playmaker, medium-brown skin, long black curly hair to the shoulders held by a thin headband, very prominent buck teeth in a huge joyful grin, wide nose, lanky loose build"
D[l06]="anime likeness of Marta, Brazilian women's football legend: woman, warm brown skin, dark hair pulled back tight into a long ponytail, strong jaw, confident calm expression, athletic compact build"
D[l07]="anime likeness of Didier Drogba: Ivorian striker, very dark skin, shaved head, short full beard, broad shoulders and powerful muscular build, towering, calm intense stare"
D[l08]="anime likeness of Lionel Messi: Argentine forward, fair skin, short neat brown hair, full trimmed brown beard, small compact build, round face, gentle humble focused eyes"
D[l12]="anime likeness of Virgil van Dijk: Dutch centre-back, light brown skin, black hair in a small top knot with shaved sides, full neat beard, very tall broad commanding build"
D[l09]="anime likeness of Zinedine Zidane: French playmaker, olive skin, completely bald head, prominent straight nose, deep-set calm eyes, clean-shaven, lean elegant build"
D[l10]="anime likeness of Ronaldo Nazario R9 (2002 era): Brazilian striker, brown skin, head shaved bald except a small triangle patch of hair at the front, wide gap-toothed grin, strong stocky build"
D[l15]="anime likeness of Kylian Mbappe: French forward, dark brown skin, very short buzz cut, youthful face with a slight smile and small ears, slim fast athletic build"
D[l11]="anime likeness of Cristiano Ronaldo: Portuguese forward, tanned skin, sharp slicked-up dark hair with a clean fade, chiselled jaw, perfect groomed eyebrows, very muscular athletic build, confident smirk"
D[l17]="anime likeness of Neymar Jr: Brazilian forward, warm light-brown skin, narrow oval face with defined cheekbones and slim straight nose, bleached-platinum-blonde short curly top with dark skin-fade sides, thin moustache and short goatee, small tattoos on forearms and neck, slim wiry build, cheeky wide smile"
D[l18]="anime likeness of Cole Palmer: English attacking midfielder, pale skin with freckles, short messy ginger-auburn hair, thin face, calm half-lidded cold expression, slim lanky build"
D[l19]="anime likeness of Lamine Yamal: Spanish teenage winger, light brown skin, short dark curly hair with faded sides, very youthful boyish face, slim teenage build, playful confident smile"
D[l20]="anime likeness of Jude Bellingham: English midfielder, light brown skin, short dark hair with a sharp line-up and fade, strong jaw, confident intense eyes, tall athletic build"
D[l21]="anime likeness of Viktor Gyokeres: Swedish striker, fair skin, short dark brown hair, stubble beard, strong square jaw, very broad powerful muscular build"
D[l22]="anime likeness of Thierry Henry: French striker, dark brown skin, completely shaved bald head, smooth clean-shaven face, calm cool confident expression, tall slim elegant build"
D[l23]="GHOST: an otherworldly pure-white character, porcelain chalk-white skin, long flowing pure-white hair, pale white eyelashes, glowing pale-blue eyes, serene eerie expression, lean build"
D[l24]="ECLIPSE: an otherworldly pure-black character, jet-black obsidian skin with a subtle sheen, short black spiky hair, glowing golden eyes, sharp confident grin, athletic build"
D[l25]="XENO: a friendly alien footballer, smooth teal-blue skin, bald head with two short antennae, large glossy black almond eyes, small nose, curious smile, slender build"
D[l26]="ONI: anime demon footballer, crimson-red skin, two short ivory horns on the forehead, wild black spiky hair, sharp fangs in a fierce grin, fiery orange eyes, muscular build"
D[l27]="KITSUNE: anime fox-spirit girl footballer, pale skin, long orange hair with white tips, orange fox ears on top of her head, a fluffy orange fox tail, sly golden eyes, mischievous smirk, agile build"
D[l28]="MECHA: an android footballer, smooth white-and-grey synthetic skin panels, glowing cyan visor strip across the eyes, no hair, sleek robotic head, calm expression, athletic build"
D[l29]="RONIN: anime samurai footballer, tan skin, long black hair tied in a samurai topknot, a thin scar across one eye, stern focused eyes, short stubble, strong lean build"
D[l30]="ASCENDED: anime power-up hero footballer, light skin, tall spiky glowing golden hair standing straight up, intense teal eyes, determined battle-ready expression, muscular build"
for id in ${(k)D}; do
  [ -f ../looks/${id}_card.png ] && [ ${id}_ref_front.png -nt ../looks/${id}_card.png -o 0 = 1 ] 2>/dev/null
  zsh gen_front.sh $id "${D[$id]}" 2>&1 | tail -1 &
  while [ $(jobs -r | wc -l) -ge 2 ]; do sleep 3; done
done
wait
echo ALLDONE
