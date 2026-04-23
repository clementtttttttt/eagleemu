num = int(input("enter fixed point num"), 16)

integ = num >> 10

if(integ & (1 << 5)):
    print("-",end="")
    integ ^= 0x3fffff
    integ += 1
frac = num & 0x3ff

print("%d.%03d" % (integ, frac))
