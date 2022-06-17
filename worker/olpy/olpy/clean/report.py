from dataclasses import dataclass, field
import collections
import random

@dataclass
class ValidationReport:
    '''
    Class for a validation report
    '''

    title: str = ""
    validated: bool = True
    issues: list = field(default_factory=list)
    sub_reports: list = field(default_factory=list)


    def __str__(self, level = 0):
        out = _get_str_level(self, level)
        if len(self.sub_reports) > 0:
            out += "".join([x.__str__(level+1) for x in self.sub_reports])
        return (out)

    def print_status(self, log_level = "all"):
        """
        Print the status of the report.

        log_level can be "all", "failures", or "none".
        """

        if log_level == "all" and self.validated:
            print(f"{self.title}: PASSED! {self.celebrate()}")
            print()
        elif log_level != "none" and not self.validated:
            print(f"{self.title}: FAILED.")
            for r in self.issues:
                print("  - " + r)
            print()

    def validate(self):
        if self in self.sub_reports:
            print("Someone goofed up and allowed self in self.sub_reports :(")
            return
        for sub in self.sub_reports:
            sub.validate()
        self.validated = self.validated and all([sub.validated for sub in self.sub_reports])

    def celebrate(self):
        exclamations = [
            "Callooh! Callay!",
            "Oh joy!",
            "Yay!",
            "Yippee!",
            "Hurray!",
            "Good job!",
            "Whoop whoop!",
            "Hot diggity!",
            "Noice!",
            "Oh yeah!",
            "Woooooooooot!",
            "Boo-yah!",
            "Ta-da!",
            "Whoopee!",
            "Woohoo!",
            ":)",
            "*dances*"
        ]
        extra_enthusiasm = [
            "This makes my day. You nailed it, my friend! Go treat yourself to a kumquat or something.",
            "I just gotta tell you how I'm feeling. Gotta make you understand. Never gonna give you up. Never gonna let you down. Never gonna run around and desert you. Never gonna make you cry. Never gonna say goodbye. Never gonna tell a lie and hurt you."
        ]
        if random.random() < .001:
            return random.choice(extra_enthusiasm)
        return random.choice(exclamations)

def _get_str_level(report, level):

    if level == 0 and len(report.title) > 0:
        title_line = f"""
#############################################################
## {report.title.ljust(55)} ##
## Valid: {str(report.validated).ljust(48)} ##
#############################################################"""
    elif level == 1 and len(report.title) > 0:
        title_line = f"\n\n༼ つ ◕_◕ ༽つ {report.title} - {f'PASSED! {report.celebrate()}' if report.validated else 'FAILED.'}\n"
    elif level == 2 and len(report.title) > 0:
        title_line = f"\n\n      ʕつ•ᴥ•ʔつ {report.title} - {f'PASSED! {report.celebrate()}' if report.validated else 'FAILED.'}\n"
    elif level == 3 and len(report.title) > 0:
        title_line = f"\n\n        ˁ˚ᴥ˚ˀ {report.title} - {f'PASSED! {report.celebrate()}' if report.validated else 'FAILED.'}\n"
    elif level > 3 and len(report.title) > 0:
        title_line = f"\n\n            * {report.title} - {f'PASSED! {report.celebrate()}' if report.validated else 'FAILED.'}\n"
    else:
        title_line = ""

    if not report.validated:
        spaces = level * 4
        deduplicated_reports = list(set(report.issues))
        lines = "".join(["\n"+" "*spaces + x for x in deduplicated_reports])
    else:
        lines = ""

    if len(title_line) > 0 or len(lines) > 0:
        return f"{title_line}{lines}"
    return ""

def _flatten(l):
    for el in l:
        if isinstance(el, collections.Iterable) and not isinstance(el, (str, bytes)):
            yield from flatten(el)
        else:
            yield el
