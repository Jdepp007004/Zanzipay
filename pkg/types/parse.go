package types

import (
	"fmt"
	"strings"
)

// ParseTupleString parses "resource_type:id#relation@subject_type:id[#relation]"
func ParseTupleString(s string) (Tuple, error) {
	hashIdx := strings.Index(s, "#")
	if hashIdx == -1 {
		return Tuple{}, fmt.Errorf("invalid tuple %q: missing '#'", s)
	}
	resourceStr := s[:hashIdx]
	rest := s[hashIdx+1:]

	rt, rid, err := parseObjStr(resourceStr)
	if err != nil {
		return Tuple{}, fmt.Errorf("invalid resource: %w", err)
	}

	atIdx := strings.LastIndex(rest, "@")
	if atIdx == -1 {
		return Tuple{}, fmt.Errorf("invalid tuple %q: missing '@'", s)
	}
	relation := rest[:atIdx]
	subjectStr := rest[atIdx+1:]

	st, sid, srel, err := parseSubjectStr(subjectStr)
	if err != nil {
		return Tuple{}, fmt.Errorf("invalid subject: %w", err)
	}

	return Tuple{
		ResourceType:    rt,
		ResourceID:      rid,
		Relation:        relation,
		SubjectType:     st,
		SubjectID:       sid,
		SubjectRelation: srel,
	}, nil
}

func parseObjStr(s string) (string, string, error) {
	parts := strings.SplitN(s, ":", 2)
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", "", fmt.Errorf("expected type:id, got %q", s)
	}
	return parts[0], parts[1], nil
}

func parseSubjectStr(s string) (string, string, string, error) {
	hashIdx := strings.LastIndex(s, "#")
	rel := ""
	if hashIdx != -1 {
		rel = s[hashIdx+1:]
		s = s[:hashIdx]
	}
	st, sid, err := parseObjStr(s)
	return st, sid, rel, err
}
