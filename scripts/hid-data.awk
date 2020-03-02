BEGIN {
	OFS="\t";
}

BEGINFILE {
	RESET_USAGE();
	RESET_STATE();
}

function RESET_USAGE() {
	N=0;
	delete USAGE;
	USAGE[0]="NOUSAGE";
	TYPE="";
}

function RESET_STATE() {
	UNIT="";
	UNIT_EXPONENT=0;
	LOGICAL_MIN=0;
	LOGICAL_MAX=0;
	PHYSICAL_MIN=0;
	PHYSICAL_MAX=0;
}

function extract(s) {
	patsplit(s, DATA, /[^()]+/);
	return DATA[2];
}


/^\s*Report ID \(/ {
	REPORTID=extract($0);
}

/^\s*Input \(/ {
	TYPE="Input";
}
/^\s*Feature \(/ {
	TYPE="Feature";
}

/^\s*(Input|Feature) \(/ {
	if (PHYSICAL_MIN == PHYSICAL_MAX && PHYSICAL_MIN == 0) {
		UNIT = "";
	}

	DISPLAY_FACTOR=10**UNIT_EXPONENT;
	switch (UNIT) {
		case "Inch":       DISPLAY_FACTOR*=1;      DISPLAY_UNIT="Inch";    break;
		case "Centimeter": DISPLAY_FACTOR*=1/2.54; DISPLAY_UNIT="Inch";    break;
		case "Degrees":    DISPLAY_FACTOR*=1;      DISPLAY_UNIT="Degrees"; break;
		case "Radians":    DISPLAY_FACTOR*=57.3;   DISPLAY_UNIT="Degrees"; break;
		case "":           DISPLAY_FACTOR=1;       DISPLAY_UNIT="";        break;
		default: print "Unknown unit " UNIT "! Exiting."; exit 1;
	}

	DISPLAY_PHYS_MIN = PHYSICAL_MIN * DISPLAY_FACTOR;
	DISPLAY_PHYS_MAX = PHYSICAL_MAX * DISPLAY_FACTOR;
	if (DISPLAY_UNIT == "") {
		DISPLAY_PHYS_MIN = "";
		DISPLAY_PHYS_MAX = "";
	}

	for (i = 0; i < N; i++) {
		print REPORTID, TYPE, APPLICATION, USAGE[i], LOGICAL_MIN, LOGICAL_MAX, PHYSICAL_MIN, PHYSICAL_MAX, "1e"UNIT_EXPONENT, UNIT, DISPLAY_PHYS_MIN, DISPLAY_PHYS_MAX, DISPLAY_UNIT;
	}
	RESET_USAGE();
}

/^\s*Logical Minimum \(/ { LOGICAL_MIN=extract($0); }
/^\s*Logical Maximum \(/ { LOGICAL_MAX=extract($0); }

/^\s*Physical Minimum \(/ { PHYSICAL_MIN=extract($0); }
/^\s*Physical Maximum \(/ { PHYSICAL_MAX=extract($0); }

/^\s*Unit Exponent \(/ { UNIT_EXPONENT=extract($0); if (UNIT_EXPONENT > 8) { UNIT_EXPONENT -= 16; } }
/^\s*Unit \(/ { UNIT=extract($0); }

/^\s*Usage Page \(/ { USAGE_PAGE=extract($0); }
/^\s*Usage \(/ { USAGE[N]=USAGE_PAGE " " extract($0); N++; }

/^Collection \(Application\)/ { APPLICATION=USAGE[0]; }
/^\s*Collection \(/ { RESET_USAGE(); }
/^\s*End Collection/ { RESET_STATE(); }
