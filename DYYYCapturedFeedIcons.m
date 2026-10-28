#import "DYYYCapturedFeedIcons.h"

@implementation DYYYCapturedFeedIcons

+ (UIImage *)iconForFileName:(NSString *)fileName matchingNativeImage:(UIImage *)nativeImage {
    if (![nativeImage isKindOfClass:[UIImage class]] || !fileName.length) return nil;
    static NSDictionary<NSString *, NSString *> *encoded = nil;
    static NSCache<NSString *, UIImage *> *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        encoded = @{
      @"like_before.png" :
        @"iVBORw0KGgoAAAANSUhEUgAAAG4AAABuCAYAAADGWyb7AAAI9klEQVR42u2ca4xdVRXHf2ve005rKbWlUIrlJWBRQIGCgMEgQYzxg4EoQowJaoKv"
        @"GAnEEP1gQkhI/GACn0g0EpToJyU8gkCUR6EUEShv2lIepQ8oZZjOnc5M587fD+d/MofrlM6UTufiXb/k5vbOnLPPnv3fa+211t63kCRJkiRJkiRJ"
        @"kiRJkiRJkiRJkiRJkiRJkiRJkiRJkiRJkiRJkiRJkiQfP+JgP1DS1DoWMdm9PcBFwFJgGJgHLAMWAUPAGuC+iNi+jz70AacApwHjQA34BLAHGPH7"
        @"k8DzEaEUbhrCVcWTtAI4HfgU0Am0AYuB5cBJQA+wC3gJeBF4H/hzRGxueHYH8BXf0wXUgV7/e49fNWCObxn0ZNjS2FYK9yGiSVoMnGPBSnEELAQ+"
        @"DZxsi+sCdgBbgLeAd4F+YC3wgO87HjgLONKCDQPdtrBOt9Fp4cYtIkC7r3kUeCoixlO4vfMr4PfAhcChwCjQYfFki1hsAfGgz6n8/h1gm4WsWcwl"
        @"dodDFmjU4rxlcdr8uduTIdzuuO/pAdZExEMtKVwpni2q0SWWPz8euMBr14DdWR3YCKz3APcCY/4btgErLPRKC/OMH9dtC2yrWFbNLvCxiNgzSf9O"
        @"shs+xvd12/3OB16OiDtbUrh9iDoX+KFnetgyuoFHI2LNPu7ttDirHHjMsQs93OtVzSI+sK8Axu0tA75msRcA2y3eExHxYAr3wYG/0oNUt2XtAO6J"
        @"iB3TbOsMr2dH+UfvAVs9AQam0U4AJziaHXHfRoF/RsSTszVWHU0kWjtwrl3ToQ4e1gF3RMTwtGdkxFpJz7ut+cDmiOjfj3YEvOhJtcoTahw4WtLm"
        @"qVjuTNDWRAZ3nAdmsdeuQeDp/RGtMui1iHgjIp7bH9EaeMFByqBd91Lgc7M1WG1NYm2dlUiuw4HHpoh4pWnypogx4F+OQAe9li6RNKeVLa7T60iP"
        @"Z3UH8HrTVSuKJHy9xasDn3Q+2bLCtTnHwov/ZrujZuQJe4Zwzri8lYVb5Yhtt2fzHq9zNKHV7ahUXerA4ZKObFXh+ryu9bk8NWYBZ3pd3V9esXjt"
        @"FnBRq6YDXe7LuAei5vVuKgL0Ap/3fcO2AgHrI2LnJNcfCxwBDHm3AeCdiHhpGv1dB5xYGcPdrSpcrwe7F9jp9xWS2iOivpekeAlwGXC+A4R2t1FW"
        @"+h+SdC/wl4iQpBOBSyhKaSd4cvR6rXpH0mrg7xFx9xT6uwOYa8HmzLR3aGbhhioz90jgVX9e5DJTI+cDN/rahRas3hCVXg58HVgp6RngWuBYij28"
        @"NkeENbvlz9iCLpb0WkScu6+kXNJuP2fUUXFLCjfXg9lXWXdHJnOXki4FbnApq91rYrevHbUFjFcqMNfZAktrHPPvhv3cknFb8WGS7gO+ERFDe3HP"
        @"PW6zrI2Ot6pwYxXBuii2ZToaUwJJ3wV+42R9uNL/DU6OB4BDgK9atNKd9Xqghyz0RuBBi3mGqzaLfP0gcDZwm6SrI+LVSfrbU8nlZiXIaxbhOitW"
        @"Uh4l6PKAl6KdZ9FKVzcCPAf8ySI8FxF1SQsp9vK+41dV/BeBm4G7yxqjpKUUW0FXAF+i2EnooCgqD0u6YpJ1dm7DxOpqZeHqTGxwzqeo5Ld5cPuA"
        @"73ldKsVcC/wyIp5qWH92Amsl7aTYp/uyk/rHHag83HD9VmCrg5PL7YYXemKcDnzB91Y5ueLG67bklhRuowONUbuv+RRHBcZsQV0WoJzhrwN/aBSt"
        @"QZANFuEGSXMjoraPgGNI0h+BSyn28g6x4JdNItwKR6PjFBusG1s1AX/c7rHfa8wI8Aaw3RZ0vdcgebAeA/46jWpHbYrXjQA/sDUN25LOlXRaxWUv"
        @"Z+IwkYBtEbG7JYWLiEGnADXncePAkoh439X3le5rO8U5kltn8Njca8BNfl54zVvVUJ4r17xR4NlWrlWWZSQ80xcAZ0pa5pC8PF9SB4Yj4p4ZnETj"
        @"wK2V4GhuKZSrLof61Qa8u5eos6WEG7JoSx26rwAWSFpJsXPQZwvYchD6Mo+J43k9wNkurR1nIXdW3Pms0NFEwm0BNnlglnm9O6tSChuzC503k53w"
        @"odl+P688fLuU4nzn0Q6QBizextkarKaxOK9z65wwb7d1LfbMHrBo40zs281UP8Y8Odor4f77wGcrlijghdk83dxMrhLnXQ9X6pZzbH3dTJw03nUQ"
        @"+rGzYuFlENLFxMHcfoozKKRwxWzfHRFPUOyAV8tLZfjdDhwn6ZwZ7spVnizl6eY+Jk45jwCPTzXFaBWLK/mb3dMez/J1lRAc4CpJM3K0QdKZwPcr"
        @"rrIfeNuTpwNYGxHrZ3uAmlK4iHgPWG2XJed4ZZTXTVFTPH8GRGun2P7paMjr3rTrXO/knxRu7zxr8Tocvb3JxHGBQ4BLXMU4UKKFy1ur+OB20vOe"
        @"NJuARxy8pHAfYnXyEe9/Oyh5pBLl9QIXUxSBDxSLKHYTqudHXvCk2QWsbqbvyDWzxZUC3m1XuYHiGzijFm8ecLUT9AORu/2Morhc7ma/6wi3Btwf"
        @"EW+Q7NfgXinpJkk7JO1RwaikNf6Cx0dp+1pJb7nNQUm7Jf1D0nWSTs/R/2iDe5ikb1u8XZpgRNLTkk7xOjWdNtskXV1pr3z/j0U7L0f+wIh3tKQr"
        @"JN0maVtFvPckPSrphOkEI5J+4XsHK229JOmnKdqBFy8kXSrpDkn1isusSbpX0qlTtN4fS9rge8f8/rqk6yUdkyM9M+K1SbpI0moLNuJXTdLDkn7k"
        @"L/7/T54m6TRJv5P0ssUqre1tSb/1t1CTGRbwQkn3Vwa/buvZJul2SYdVrp0v6Vu2sm0OcEpLe03SjZIW5agePPGOkHSzxahXApZdkrZKukbSckm3"
        @"+HPdopXW9qykbzolSGbBdV4jaZMFUWXtG5Q0UPnZkN+3SLorw/3ZF69T0gWS7tTklLnfgNezX0s6KkeueQRcIOknzsWGJL3phLrfFnmLpC9+3P/O"
        @"+D8WsA/4OXAqxRbRCHD7bP//JEmSJEmSJEmSJEmSJEmSJEmSJEmSJEmSJEmSJEmSJEmSJEmSJEmSJEnSyvwXOYL5/65fj2QAAAAASUVORK5CYII=",
      @"comment.png" :
        @"iVBORw0KGgoAAAANSUhEUgAAAG4AAABuCAYAAADGWyb7AAAIl0lEQVR42u2cbYxcZRXHf2d2trvtllZapJS0oFKwkvoCEcRYCZEgJr41xBpRU/lg"
        @"UyVqogIG/IAaI4ZoIqb6RdGkIcXEyKtRsQRbqNa1QRuTqrHVWpHyktIu2+77zPz9cM/NPnuZ2aXb3Z3pzvklN3N35u69zzz/55znnOdlIAiCIAiC"
        @"IAiCIAiCIAiCIAiCIAiCIAiCIAiCIAiCIAiCIAiCIGg5bD58CUkXAK8FjgGdgIBy/nHyPS3524AqMATUgMXAWcALZnY4hJs9sS4F3uhCvd4FWAws"
        @"cEEsEa7e9xbQ4UfFjw7gJeB/QBewx8yeCeFmRrBLgDcDa7yiT7pYFWCRv44C3QXhVPjeBoy5ZebnHUDJLbDqjeI/QK+ZHQrhpidYCXgv8Fav3GGv"
        @"3FXAoAvV799pgQulgnA1/18rWF3NLTavjxFguVvfEn9vp5k9GcKdunAbgLd5JY/426N+fhLYD/zD3y+75S3w68dcMFzskr92+z3Kfn4x8AbgXBd0"
        @"GXDEz88HdgFPmNlgCDe1YIuA9cC7XYA+d2H9wJ+BfWZWnYXnXgZc4v3nmPd5o8Ah4JdmNhLCTV6BH/QKrHrUNwDsBfaa2fAsP7vHn32tN5aXgRXA"
        @"k8DuZopnLS7a+93SlnuLr7loz7qLrAI97hbHkv6ry/us3C3mqUEFOAEcB44CC19N6C/pLcAH3GUO+Wuvme0M4SZW1BUe6t8BvMnffh44b5q3rHpl"
        @"F3kO+DnQCzxsZgOTlOkq4BoXf6nne1tDuKxyzgFuAj7iIf+ixFLKnmAvO83H1JJoEregUeAB4DHg0UbBh6QbvfF0+rHbzHa1tXCSbgC2AFcAZydW"
        @"csL7trTiS9MQq9H/jPpz5O7zXuDrZjZWp4xLgc96P9vj0eyPZ7uvrUe5RUTbDNzllVFMnA8D24EXgYXe0oeTSK9W6MPKhf/PU4NhF6/T318LXAdc"
        @"5A24AzgH+KLf99Y6RR0GngKuTvK+17gbby/hJF0HfMUDkLSCHgXuBx6ZjXDfn70SeB9wO7DaG00ZuEWSzOy2Ce7JbERSX5JL9nhfPOfClVrA4G7y"
        @"XCnnGPBNYJOZPThborkQz5nZT71P/Unh489I+pKkzsL7Qz5Ss8Q9wAraDUlfkzSqcY5Jut2Ht+a6LCbpTkkVL8uIpH9KWlO4rixpk6TbJH1Z0qZm"
        @"1F2zLW5z0udUgLuBu82sNudRmpmAHwC/SobBVgLf8EQ8pzsZcmuUZsxf4ST9yIOB3BX+2sy+PZuu8VWIdxT4mY+QlDyiPT9JSzCzk0k6UKb+tNG8"
        @"trjXJaH4YJ0+plnibQced/FWejnfVbhsxAMUEuub/8L5ENJasolPgBfN7KEW6n7/4IEHLt6lhc8X1Unk28LirvQkO+dAi8VNf/I+F7KpoQVpEOOe"
        @"otrMPq5ZedxCz4HyEY3Hp7DQ84CvAus8Z+pJWns+ajFqZh+fofK9UOi71KDuRpvV+JslXD65mUeUfZOIttijvetd8FIyVGV+j6HsUm0DNs/AdEvJ"
        @"79/TwDN1Jv1zpZ1cZY3xcdLaFB38dWRTOwsL5V2QCN/lx/XAxpmIUaZIG/LD2k04c2vPO/jyJBX1INmSgVoSyRXzvAG3ul4zu2+GytdZz1X64ECF"
        @"8WWAne3kKvM1jbWpWriLt1HSO4ALyUbku5m4/K4fGDCzPTNYvrRf6yj0z53Jd1jQbsKlofSU7sbMeskmPOckYymUKbWqZWTjlPnSvpPt5Crlz86P"
        @"VpuJLxUsLhVuOdn8oNzaDrSbcLirqdCadDZwlYv9s5ILd7BdXeWUM9qS1gMbvLWrYKGlpHLzYKeahPSdSfhe9vOnga2TzFynwU/V3WK+R+EysiG6"
        @"Ktmio8F2Ei5f7p0HKF1T5HG3kq2yykWbrqeouYDXeIX/sMF1edny8+NejsvdTeZByRP1ljjMd1dZY3yt/olJrr3WDyXXn8737fYAY/Uk11UK7rGL"
        @"bJXzWsb3KQyRLRWknYRbSrYwJ2/RqyaJJh8GHvKhrWG3mNyFVZP8rpoclQYub9St/SDZQHIjFhW80du98ZzlUWQPsL+ZU1DNcpUDHlLn/dtHyRYL"
        @"NeLTZvZJn9DM3VhHnUQ8teg8iR5jfFNIGahOtn7S6S8ETcuSBjEC/MvMftvMyKlZwj0G7AOuykNsSUvMrL+B1Q3768BpPPNUgogPM3FJ4IA3sC6y"
        @"VdS/aYV8Ze5DSrN/u7XkUd1q4BOtkANIOhf4UPLWcbIFTGeTbTJ5xMyGaFckbdZEDkla0QLl+pSkPi9TVdIzkr4jaYOkLgKQtK8g3nebXJ51kp5K"
        @"yjMg6T5JV4daEyvqxoJwz0v6WJPKcpGk3xfKs1PSlaFU/Qp7oLC28r+Sts6l25S0XtJfJY0l5Tjg27yCBpW2StIur6xK0rcclPQ935F6OvcvTfJZ"
        @"p6Tve/+q5NmSdEcr15u1iHgrgN+R/ZLCCOOrv2D8pyt2AzvINtH/fZJ7dXu+tYXx+buqJ9UiWyd5MXCBJ/79ZBs3Bsjm2gbI9i3cbGYvh2lNLV7Z"
        @"+5hRb/VVvZIhSU/7xsdG97nBl45X/Poio3WsK7/uoKTPhRrTc5s3S+qV9JLqM+jbsl6Rf0m6RdKzOnWOSfqFr/cMTtP6Pi9ph6T9Bes4IelbksrJ"
        @"9as9tRhsYKn1OCJpj6RtxY0dZwJnwq8uLAHuIduOhfdX95rZFkkdZL+KsJ3sN1Dyz0fINiD+xc9FNsC81EdrjgA7Wu3XguajBX5B0tHEWra5a7xT"
        @"0t8KfWCfu70Lo+aaL9w7fegpd4N7JW2v4/76JN0laW3UWuuId7gQARY5Kmld1FTrCfceHxIrUvWocFnUUuuKt1HSH5O0oF/SPZIub7e6OBN/r3IN"
        @"2a4dA06a2Y5o0kEQBEEQBEEQBEEQBEEQBEEQBEEQBEEQBEEQBEEQBEEQBEEQBEEQTJ//AzklefPG97gNAAAAAElFTkSuQmCC",
      @"unfavorite.png" :
        @"iVBORw0KGgoAAAANSUhEUgAAAG4AAABuCAYAAADGWyb7AAAGv0lEQVR42u2cW4xdVRnHf2umM9OZKbQQW2jshUi5WVORZkoJWJIq+kATUJISNKJP"
        @"NjUkamKMiTH40ERDiNEGgz4YxBfTyCWWigVDjU2wY6GEBIkVgkALtFNLO3Q6rXPr34f9nbC72XMu0zJzmPP/JScze++1115n/ff61vetywFjjDHG"
        @"GGOMMcYYY4wxxhhjjDHGGGOMMcYYY4wxxhhjjGlp0mz7QpKWAXOBCaADeD2lNGLhmlewXuBLwAXAMuBEiPdfYDCl9LiFaz7RVgAbK4dAJzAeLa4D"
        @"GADeSyk9PFuEa5sFon0c+GII1h5CHY/LY8C7wHxguaQ7Zotwc2aBaHcAC4DhEO9/wD+AQ8BaYCkwGv3eJyUdB3anlMYt3MxxC9AT/58BDgN/TClV"
        @"WtwBSauBzwLzgJPATcBbwCs2lTPT2j4HXB5idEZr25YTLevEU9oHvBzCpnBYNkjqsXDTL9pq4HpgELgkTOHfU0qnSz2wlP4CvAr0hkntBTZZuOnn"
        @"MmBROCOjwLMppb017nkUOAh0R8trl7TKwk1fa1sLfCb6s3bgrZTSMzXjnqw17g7R2uKzTtJcC/fhizYHWBku/nsRZD+Xuz5P0kJJl0paKmmBpG5J"
        @"HZHkNeBf4XmOh3N2vQPw8y/UMqAvRkO6gCvi0xUV3wO8EX/7wgxeFM5KWzgip0PgQ8A7wBBwITAS6U8AzwNHov8bTCntsnCNCbU8XPf14b6vAq6a"
        @"5mKcAv4agu4HngAOppSOWrgPCnYjsAG4FVgSrWamqZjSAeBt4BfAk80m4EyK9h1Jw5LGNLOM15HmJUmLWr7FSfoa8GDEVUUGwly+Cfwc2BHnuyME"
        @"6I5+qjP6spPhZZ6KdO3x/ebk+jzF39HcqNFQXF8KfJts3LMjrl9QUq6/AV9OKR1r1Za2TtKpwhs9KOkPku6SNG+GypUqjpGkn0l6saTlPSqpu1WF"
        @"e6xQGY9LuqkJy7lI0tclTRTKe3urCnciKmBC0lFJFzV5ee8uCHdvqwfgbWTLC443+bv2dOH4cKsKl3eMhs+hJSyRtLiOdD2SLj6H8nYWjhe1qnD5"
        @"McIr66n8EjE2A78HtsXyhcnSfQLYDuyQdOcUy3tj4XiiVfu4p3L9xZikLQ3e3yFpfy6PB6qkfTKXrn8qHqukA4U+7u5WFW51IfA9JGlNA/f3Rvhw"
        @"Ou5/qkraQ5JG4jMk6ZoGy/qDgmg7msExmCleBF6IQBngUmBTbiS/Zn2SDSBXTG61tZNj0Ud1RqA+twHRbgB+Ujj951Yf7vpKDHcpN+S1uYEWN5Rr"
        @"BY9VSftuIci/rgHH59lCa9uJgQi8i8HtbXXc1xUmsB7h8unelnT1FPphhVn+vFV738nYVzKs9JtqQXlMmh7Mpd9eJe3ruXQHY56vWpn6JB0plGdC"
        @"0jes2NkV1S5pV4l4L09m1iS1SXpQ0juSDku6r0r+t0kaCNF21CjLlpJyDEjaZKXKK+xCSb8rqbR9Nczlakk3S5pfI/81kq6tNi0Tfe5g4fkHWnZc"
        @"sgHxPhbiFefmtta4L52HZ88pxGrHok/bYGXq9xa3FN784Wl47pLCy9Iv6dpmraemW+WVUqrsAZhfiPk+bMYKx5eRTbJauAYovuk/nIYXZoBsYVCF"
        @"TmC5bWD9JmtdwRUfbmA05VyffU/BXD7UrAtmm7HFXQUszB3vTCmNTdOznyfbyVNhKU06C9CMwo2RLeY5E8cPTWP/2k+22rlCDx+ch7Nwk3A176/K"
        @"ggb38EVgfo2k6xpdSiepjbMndS8GFlu4OoJwspXMZ51u4P4VwGZgF/AM8GtJfQ20uDMlZvtmC1ebBWT73fKM1ilaH/AI8ADZFNFc4HZgr6Rf1uNk"
        @"RCDfVTjda+FqcwL4T+HceI3KXizpC8CfgE/nLuWF+hbwqzomarsLzsgY2c9tWLgapmoQ2FM43VNFtLXANrKJzYU1sv8q8ISkeyV1TZLmDNkWrAqv"
        @"AHsxdZm8bxaHniZJtzXGEkdKBqbvkbRK0p6Sa6MxS7CxJM+NuXQnJe2OftfUIdyaECQ/0Lw1xjBXStpZZVNGv6SVhfx+HCKUcTRmBFbG59+F67+N"
        @"XywydYr305JKrrab54ik+yfb0y3pe5K259KfqpH3UCx3+JTVaEy4xSVrPfIz0RVGJD0iaX0defZK+pGkf9a5zeq7VmJq4q0IUzVRUskH4totU8j3"
        @"Eknfl/TcJHnvl7Qp9ps3LekjIOB6stmCLuBYuOwPn4+9BjGzfTnZPrgOoB/Y412nxhhjjDHGGGOMMcYYY4wxxhhjjDHGGGOMMcYYY4wxxhjT9Pwf"
        @"4mSLXzeKjPcAAAAASUVORK5CYII=",
      @"share.png" :
        @"iVBORw0KGgoAAAANSUhEUgAAAG4AAABuCAYAAADGWyb7AAAGfUlEQVR42u2cbYxdVRWGn9VpO9OZAk5oKSgp30iqUapIQpvYiQalBAMaTJFg/VGM"
        @"CYnfRiBFJYEfYGhN+AEJ0VDQKLGSaDCEELCiKR8SIYYUgcRAq3TSSluh05lOZ9qXH2ddenrozJz5aHvqvE9yc+49956996z3rL33WnufAWOMMcYY"
        @"Y4wxxhhjjDHGGGOMMcYYY4wxxhhjjDHGGGOMMeb4I2yCAkkL0h6LgUHgWWBWRLxt6zRPrIWSLpW0QdIOSe9I6pc0LOktSa9LWm1LNUOsD0m6UdIP"
        @"JW3VoewpvR8uvX/EXeXRF2o+sAA4F1gJnJndYV2GgFnAC8AXI2KLhTuygvUAFwGXAEvS+CePcslu4FagG9gLLAI+m6KT554CroqIve67plasDkl3"
        @"SXoix6w63Cvp45LOP0x5qyTtLP12t6TltvTUiNUt6RxJvZIGawi1LV/X1iz/5sr1zzXh7555nIp1HnBhvr4NdI1xyRZgA/AKcF9E7BxHdRuAPaU6"
        @"5tpdxidWm6SbJP1K0ksVL9h3GM96Q9KDkq6V9LFJ1v1iqdzXJYU9bnSDnQWcA9wNnAZ0ArMP89NZeewFXgPuBX6XAfRUTCSGS+8PRIQs3PvFWgT0"
        @"AGcD38/ZXMcIP9+TM+NfAm8Bd0fE9tL3+6diwgOcUDrV5jHuUAPNBW4GllfirKpoe4FNQD+wFuiNiCM5YZgDnNi0EKpJHncfsAKYMcL3m4A/AK8C"
        @"jwODEbHrKLTrvEr8N+wZR+FpCzLukqShSrppv6TbJF0i6ZRj1L4vZf6yxRZ7XMENmaFotWc/8D/g6oj4cwPad2Z2ly22N0G4GcfY22YAy0qn+oDv"
        @"RMS8hohGRTSAzdNeOOALJeH2Af8C1jesN6+GH/+wcEVcVu6274mIbQ0fll+xcNBeej8IbG2gUMOVuNBjHDBQGUuWNVC4chCvqQjq/x+Ee6PiZVdL"
        @"urBpEUsl+I5pL1xmPF6sTL3vlNSkxEBLqAOVz9Pa4wAeyTCgxeeA3ZJ+Imm+pPaGeJwqAhpJfxxl4XNzini5pE8dg7bdVGlPjxU7aJwPSLq/xup1"
        @"r6TfSPqFpM8cpbatruz8+rQVe7+RLpf0cs29Iv25BeFPuT+y8wi1aW2pzkFJS63UyMZaIekhSX+VtH2EFe4yfXlcJ2lpLhFNRTvaJT1cWWlfZoXq"
        @"Ge82SY9KeiEFGkvIYUm/nux2hax7vqSnS2UPNEW442Gz0N8p8pgDwCkUa3FXAqdTbHL9aOX3bcBXgPMl3RgRT06i7k5gXunz3krSwMKNcMcvTIE6"
        @"gB0U2xOej4gn8vuPAJflVP1bwBl56dvAJ4E7JK2MiH9OsAldwEmlz/sotks4jqsR/HanEPOAV8tPz0TEpohYExFrKdJld2ZKqmXsiyi2702UEzh0"
        @"j8kuih3PFq5GjzBEkccMim0LI2VhNgM/An6ap4byeL2klROs/0Al4N6RN5GFG4NWZn4gDdg3qntGDAF3Aes4uGWvDXhA0jcmKFyZN5vyvFzThVMK"
        @"0J8eN2aslruUv5mTmDK3SLpukjba3hTDNF24k1Ow2fkaqjUwRvQBV1CsPrQ4HbhBUvc46m+r2GjAwtXj1EqXVctwuZdlMbCx8tVi4AfjnBxFpQdo"
        @"zODf9DFO6Wn76nSVks4APp+z0c0Uz3JfnDdpB/BdSYqIW2oKV12Ps3A1+G+K15XHOWOI9lWKNb1Wl9oHPJYeuyTPzQFWS9oaEffUHGcbJ1zTu8pt"
        @"afSTcoKyRFLXYQRbKmkVsDAD5NklT30+Y7xnKpetkXTuGPX3cOj285kWrt4koxd4M2OntsyMrJLUI2mupLMlraDYUHtqihU5E90KrI+IRyNiGFgF"
        @"/KdUfAfws5HEy1zn9RWx/tKkzESz44FizLomhRtOD+zKYLizEq8N5gRmY2ZZ+iplLQd+DnywIsY1eZO858HA/RTPDbR4LSI+bOHGJ9584Os5Pg1Q"
        @"pLU60xNb498siidPfxsR/aOUdSXw+yynNWbuTM+emTdAd4Yi5R5p0SRyntNTuDR4O/BlihWCORxMhSmN/lJE/K1mWWuA742j+gcj4muYSQm4QNIn"
        @"ckJycT4IOZFybs//HqTSk0EtduXx35J+3Mjxf5rfBFcA1wEXUKwEzAbeyW53I7AuIp6yuzRTvI48Rv67qPbMvBhjjDHGGGOMMcYYY4wxxhhjjDHG"
        @"GGOMMcYYY4wxxhhjjDFminkXaVeuEThiyB4AAAAASUVORK5CYII="
        };
        cache = [[NSCache alloc] init];
        cache.countLimit = 28;
    });
    NSString *dataString = encoded[fileName];
    if (!dataString.length) return nil;
    CGSize originalSize = nativeImage.size;
    if (originalSize.width <= 0 || originalSize.height <= 0 ||
        originalSize.width > 150 || originalSize.height > 150) return nil;
    // Native AWEFeedVideoButton owns hit testing and spacing. We only render
    // a 20-22pt visible screenshot-shaped glyph inside its ORIGINAL image bounds.
    CGFloat displayScale = UIScreen.mainScreen.scale ?: 3.0;
    NSString *key = [NSString stringWithFormat:@"%@-%0.2f-%0.2f-%0.1f", fileName, originalSize.width, originalSize.height, displayScale];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;
    NSData *data = [[NSData alloc] initWithBase64EncodedString:dataString options:0];
    UIImage *source = data ? [UIImage imageWithData:data] : nil;
    if (!source) return nil;
    // The padded 110x110 PNG has a 48-54px glyph in its centre. Drawing the
    // canvas at 44pt gives Douyin's ~20-22pt artwork, without enlarging the
    // original button image frame. Center clipping handles smaller native sizes.
    UIGraphicsBeginImageContextWithOptions(originalSize, NO, displayScale);
    const CGFloat artworkCanvas = 44.0;
    CGRect rect = CGRectMake((originalSize.width - artworkCanvas) / 2.0,
                             (originalSize.height - artworkCanvas) / 2.0,
                             artworkCanvas, artworkCanvas);
    [source drawInRect:rect];
    UIImage *drawn = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImage *result = [drawn imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    if (result) [cache setObject:result forKey:key];
    return result;
}

@end
