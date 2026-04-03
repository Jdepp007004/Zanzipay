package lists

import (
	"math"
	"unicode/utf8"
)

// JaroWinkler computes the Jaro-Winkler string similarity.
func JaroWinkler(s, t string) float64 {
	jaro := jaroSim(s, t)
	prefix := 0
	maxPre := 4
	if len(s) < maxPre {
		maxPre = len(s)
	}
	if len(t) < maxPre {
		maxPre = len(t)
	}
	for i := 0; i < maxPre; i++ {
		if s[i] == t[i] {
			prefix++
		} else {
			break
		}
	}
	return jaro + float64(prefix)*0.1*(1-jaro)
}

func jaroSim(s, t string) float64 {
	if s == t {
		return 1.0
	}
	ls, lt := utf8.RuneCountInString(s), utf8.RuneCountInString(t)
	if ls == 0 || lt == 0 {
		return 0.0
	}
	matchDist := int(math.Max(float64(ls), float64(lt)))/2 - 1
	if matchDist < 0 {
		matchDist = 0
	}
	sRunes := []rune(s)
	tRunes := []rune(t)
	sMatched := make([]bool, ls)
	tMatched := make([]bool, lt)
	matches := 0
	transpositions := 0
	for i, sr := range sRunes {
		start := int(math.Max(0, float64(i-matchDist)))
		end := int(math.Min(float64(lt-1), float64(i+matchDist)))
		for j := start; j <= end; j++ {
			if tMatched[j] || sr != tRunes[j] {
				continue
			}
			sMatched[i] = true
			tMatched[j] = true
			matches++
			break
		}
	}
	if matches == 0 {
		return 0.0
	}
	k := 0
	for i, sr := range sRunes {
		if !sMatched[i] {
			continue
		}
		for k < lt && !tMatched[k] {
			k++
		}
		if k < lt && sr != tRunes[k] {
			transpositions++
		}
		k++
	}
	return (float64(matches)/float64(ls) +
		float64(matches)/float64(lt) +
		float64(matches-transpositions/2)/float64(matches)) / 3.0
}
