import { describe, expect, it } from "vitest";

import { coreRegistry } from "../../src/templates/index.js";
import { skillName } from "../../src/pack/skill-names.js";

/**
 * A skill is named or it honestly has none, and both answers are load-bearing.
 *
 * The one thing that must not be missing is a name for a skill a shipped
 * template exercises: such a template can be issued, so its skill can reach a
 * history entry, so it needs a title. At the other end, a generic default
 * chosen here would take the choice away from whoever is writing the screen,
 * who is the only one who can make it.
 */
describe("a skill has a name, or honestly has none", () => {
  it("every skill a shipped template exercises is named", () => {
    const skills = [...new Set([...coreRegistry().byKey.values()].map((t) => t.skillId))];

    expect(skills.length).toBeGreaterThan(0);
    for (const skill of skills) {
      expect(skillName(skill), `skill ${skill}`).not.toBeNull();
      expect(skillName(skill)).not.toBe("");
    }
    console.log(`  skill names · ${skills.length} shipped skill(s), all named`);
  });

  it("and one nobody has named says so rather than guessing", () => {
    expect(skillName(7)).toBeNull();
    expect(skillName(0)).toBeNull();
    expect(skillName(-1)).toBeNull();
  });
});
