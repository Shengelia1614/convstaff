#synthesia video to midi converter

this is pretty easy algorythm and doesnt do anything crazy 
if i wanted that i would try to utilize audio layer with it too to deal with more "colourful" videos that have crazy effects

currently its quite limited and only works on videos that are relatively "clean"

here is the example of "clean synthesia like video:
https://www.youtube.com/watch?v=QMKfJwvHfoI&list=RDQMKfJwvHfoI&start_radio=1

videos like these should work perfectly without issue

also there are some ways to optimize current code and only place i show conversion status is in debug prints rather than in ui so just no that its not stuck it usually has to process like 20k frames or something

i made ai generate documentation.md to explain whats going on in the code, i didnt read it (shocking i know) so idk if it actually correctly wrote what the code does, you can look at the code too if you want i think its pretty readable

videos that will probably not work due to it utilizing video layer rather than audio layers:

1. videos that have HUGE light bleed due to each key stroke being brighter than the sun. yeah like forget about it i tried some videos and it can struggle
1.5. so therte is option in the ui its the third check that ask to distinguish left and right hand which now does not do what is currently written, you must leave it like that do not turn it off, that was me experimenting with how to deal with the videos mentioned in 1. above, basically on most synthesia there is no big light bleed however left and right hand colours are often different so that is what the checkbox accounts for and it should STATY ON EVEN if its single colour, reason turning it off was required when testing for type 1 videos is because in those cases light up is usually in single colour and to be able to detect presses correctly its hell of a lot more accurate to take peak value of light and ignore  any other colour deviation like for example agressive bleed to other keys
2. videos that do not light up the actual keys, this code looks at the strip of rows on piano keys, now technically this can be fixed in future but cmon most videos already do light up piano keys
3. if there is live playing by hand, as in if hand is covering the piano when key is struck, again the keyboard part is basically what the code looks at so its important that that part of the video is clean
4. the videos where its not full 88key piano, boss sheet music youtube channel is basically the biggest sinner here, he sometimes uploads videos where its basically little bit cut off but given the fact that he's channel is pretty big i will be adding the feature of detecting piano even if its cut off next
