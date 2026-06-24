import argparse
import os
import random
import sys
from datetime import date, datetime, timedelta

import pymssql

try:
    from faker import Faker

    _faker = Faker("en_US")
except ImportError:
    _faker = None

_FALLBACK_FIRST = [
    "Liam",
    "Olivia",
    "Noah",
    "Emma",
    "Mateo",
    "Sophia",
    "Amir",
    "Ava",
    "Diego",
    "Isabella",
    "Kai",
    "Mia",
    "Ethan",
    "Aaliyah",
    "Lucas",
    "Harper",
    "Elijah",
    "Camila",
    "James",
    "Luna",
    "Benjamin",
    "Layla",
    "Henry",
    "Zoe",
    "Owen",
    "Maya",
]
_FALLBACK_LAST = [
    "Garcia",
    "Smith",
    "Johnson",
    "Martinez",
    "Nguyen",
    "Brown",
    "Lee",
    "Begay",
    "Lopez",
    "Davis",
    "Yazzie",
    "Wilson",
    "Anderson",
    "Thomas",
    "Chavez",
    "Romero",
    "Sandoval",
    "Tsosie",
    "Patel",
    "Williams",
    "Vigil",
    "Trujillo",
    "Montoya",
]


def first_name():
    return _faker.first_name() if _faker else random.choice(_FALLBACK_FIRST)


def last_name():
    return _faker.last_name() if _faker else random.choice(_FALLBACK_LAST)


def middle_initial():
    return random.choice("ABCDEFGHJKLMNPRSTW")


SEX = [("Female", 49), ("Male", 49), ("NotSelected", 2)]
SEX_IDEA = [("Male", 64), ("Female", 34), ("NotSelected", 2)]
HISPANIC = [(True, 30), (False, 70)]

RACE = [
    ("AmericanIndianorAlaskaNative", 6),
    ("Asian", 10),
    ("BlackorAfricanAmerican", 18),
    ("NativeHawaiianorOtherPacificIslander", 4),
    ("White", 57),
    ("TwoorMoreRaces", 5),
]
RACE_COUNT = [(1, 80), (2, 15), (3, 5)]

DISABILITY = [
    ("Autism", 12),
    ("Deafblindness", 1),
    ("Deafness", 1),
    ("Developmentaldelay", 5),
    ("Emotionaldisturbance", 5),
    ("Hearingimpairment", 1),
    ("Intellectualdisability", 6),
    ("Multipledisabilities", 2),
    ("Orthopedicimpairment", 1),
    ("Otherhealthimpairment", 17),
    ("Specificlearningdisability", 33),
    ("Speechlanguageimpairment", 14),
    ("Traumaticbraininjury", 1),
    ("Visualimpairment", 1),
]

ENV_SCHOOL_AGE = [
    ("RC80", 67),
    ("RC79TO40", 16),
    ("RC39", 13),
    ("SS", 1),
    ("RF", 1),
    ("HH", 1),
    ("CF", 1),
    ("PPPS", 2),
]
ENV_EARLY_CHILDHOOD = [
    ("REC10YSVCS", 60),
    ("REC09YSVCS", 16),
    ("REC10YOTHLOC", 6),
    ("REC09YOTHLOC", 3),
    ("SC", 2),
    ("SS", 4),
    ("RF", 2),
    ("H", 2),
    ("SPL", 5),
]
SPED_EXIT_REASON = [
    ("HighSchoolDiploma", 35),
    ("ReceivedCertificate", 8),
    ("ReachedMaximumAge", 4),
    ("Died", 1),
    ("MovedAndContinuing", 22),
    ("DroppedOut", 12),
    ("Transferred", 10),
    ("WithdrawalByParent", 8),
]
EXIT_WITHDRAWAL = [
    ("01911", 40),
    ("01912", 20),
    ("01913", 15),
    ("01907", 10),
    ("01923", 8),
    ("01927", 7),
]

SCHOOL_TYPE = [
    ("Regular", 78),
    ("Alternative", 10),
    ("CareerAndTechnical", 7),
    ("Special", 5),
]
NSLP_STATUS = [
    ("NSLPWOPRO", 25),
    ("NSLPPRO1", 15),
    ("NSLPPRO2", 15),
    ("NSLPPRO3", 15),
    ("NSLPCEO", 15),
    ("NSLPNO", 15),
]
POVERTY = [("Neither", 60), ("LowQuartile", 20), ("HighQuartile", 20)]


def weighted(options):
    values, weights = zip(*options)
    return random.choices(values, weights=weights, k=1)[0]


def distinct_weighted(options, count):
    chosen = []
    pool = list(options)
    while pool and len(chosen) < count:
        pick = weighted(pool)
        chosen.append(pick)
        pool = [(v, w) for v, w in pool if v != pick]
    return chosen


def age_to_birthdate(age, school_year):
    reference = date(school_year - 1, 6, 1)
    start = reference - timedelta(days=int((age + 1) * 365.25))
    end = reference - timedelta(days=int(age * 365.25))
    span = (end - start).days
    return start + timedelta(days=random.randint(0, max(span, 1)))


def grade_for_age(age):
    if age <= 3:
        return "PK"
    if age == 4:
        return "PK"
    if age == 5:
        return random.choice(["KG", "PK"])
    if age == 6:
        return random.choice(["KG", "01"])
    if 7 <= age < 17:
        return str(max(1, age - 5 + random.randint(-1, 1))).zfill(2)
    return random.choice(["11", "12", "13", "UG", "ABE"])


def random_date_between(start, end):
    if end <= start:
        return start
    return start + timedelta(days=random.randint(0, (end - start).days))


def build_organizations(lea_count, school_count, school_year, run_dt):
    rows = []
    schools_per_lea = [school_count // lea_count] * lea_count
    for i in range(school_count % lea_count):
        schools_per_lea[i] += 1

    effective_date = f"{school_year - 1}-07-01"
    school_seq = 0
    for lea_index in range(lea_count):
        lea_state_id = str(9000 + lea_index + 1)
        lea_nces = "35" + str(lea_index + 1).zfill(5)
        lea_name = f"{random.choice(['Mesa', 'Rio', 'Sierra', 'Cottonwood', 'Sandia', 'Pecos', 'Zia', 'Mesilla'])} {random.choice(['Valley', 'Public', 'Municipal', 'County', 'Consolidated'])} Schools {lea_index + 1}"
        for _ in range(schools_per_lea[lea_index]):
            school_seq += 1
            school_state_id = f"{lea_state_id}-{str(school_seq).zfill(3)}"
            school_nces = lea_nces + str(school_seq).zfill(5)
            band = random.choice(["Elementary", "Middle", "High", "Academy"])
            school_name = f"{last_name()} {band} School"
            rows.append(
                (
                    lea_state_id,
                    lea_nces,
                    lea_state_id,
                    lea_name,
                    f"https://lea{lea_index + 1}.k12.example.us",
                    "Open",
                    effective_date,
                    "NOTCHR",
                    0,
                    "RegularNotInSupervisoryUnion",
                    school_state_id,
                    school_nces,
                    school_name,
                    f"https://sch{school_seq}.k12.example.us",
                    "Open",
                    effective_date,
                    weighted(SCHOOL_TYPE),
                    "None",
                    "No",
                    "NotVirtual",
                    weighted(NSLP_STATUS),
                    "No",
                    0,
                    weighted(POVERTY),
                    0.0,
                    str(school_year),
                    run_dt,
                )
            )
    return rows


def build_students(student_count, organizations, school_year, idea_rate, run_dt):
    schools = [(r[0], r[2], r[10]) for r in organizations]
    enrollments = []
    races = []
    disabilities = []
    sped = []

    base_exit = date(school_year, 6, 1)
    for n in range(student_count):
        student_id = "S" + str(100000 + n)
        lea_state, _, school_state = random.choice(schools)
        is_idea = random.random() < idea_rate

        age = random.choices(
            [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17],
            weights=[2, 4, 8, 9, 9, 9, 9, 9, 9, 8, 8, 7, 6, 4],
            k=1,
        )[0]
        birthdate = age_to_birthdate(age, school_year)
        grade = grade_for_age(age)
        sex = weighted(SEX_IDEA if is_idea else SEX)
        hispanic = weighted(HISPANIC)

        entry = random_date_between(
            date(school_year - 1, 8, 1), date(school_year - 1, 9, 15)
        )
        exited = random.random() < 0.12
        exit_date = (
            random_date_between(entry + timedelta(days=20), base_exit)
            if exited
            else None
        )
        exit_type = weighted(EXIT_WITHDRAWAL) if exited else None

        school_days = 180
        days_absent = round(random.uniform(0, 25), 2)
        attendance = round((school_days - days_absent) / school_days, 4)

        enrollments.append(
            (
                student_id,
                lea_state,
                school_state,
                first_name(),
                last_name(),
                middle_initial(),
                birthdate,
                sex,
                int(hispanic),
                entry,
                exit_date,
                exit_type,
                grade,
                str(school_year),
                school_days,
                days_absent,
                attendance,
                run_dt,
            )
        )

        for race in distinct_weighted(RACE, weighted(RACE_COUNT)):
            races.append(
                (
                    student_id,
                    lea_state,
                    school_state,
                    race,
                    datetime.combine(entry, datetime.min.time()),
                    run_dt,
                )
            )

        if is_idea:
            dis_start = random_date_between(entry, exit_date or base_exit)
            sped_exits = random.random() < 0.15
            dis_end = (
                random_date_between(dis_start, exit_date or base_exit)
                if sped_exits
                else None
            )
            disabilities.append(
                (
                    student_id,
                    weighted(DISABILITY),
                    datetime.combine(dis_start, datetime.min.time()),
                    datetime.combine(dis_end, datetime.min.time()) if dis_end else None,
                    run_dt,
                )
            )
            if age > 5 or (age == 5 and grade not in ("PK",)):
                ec_env, sa_env = None, weighted(ENV_SCHOOL_AGE)
            else:
                ec_env, sa_env = weighted(ENV_EARLY_CHILDHOOD), None
            sped.append(
                (
                    student_id,
                    lea_state,
                    school_state,
                    dis_start,
                    dis_end,
                    weighted(SPED_EXIT_REASON) if dis_end else None,
                    ec_env,
                    sa_env,
                    run_dt,
                )
            )

    return enrollments, races, disabilities, sped


def qualified(schema, table):
    return f"[{schema}].[{table}]"


def insert_many(cursor, schema, table, columns, rows):
    if not rows:
        return 0
    placeholders = ", ".join(["%s"] * len(columns))
    column_list = ", ".join(f"[{c}]" for c in columns)
    sql = f"INSERT INTO {qualified(schema, table)} ({column_list}) VALUES ({placeholders})"
    cursor.executemany(sql, rows)
    return len(rows)


def connect(args, database):
    return pymssql.connect(
        server=args.host,
        port=str(args.port),
        user=args.user,
        password=args.password,
        database=database,
        autocommit=False,
    )


def find_staging_location(args, candidates):
    report = []
    found = (None, None)
    for database in candidates:
        try:
            probe = connect(args, database)
        except pymssql.Error as exc:
            report.append((database, f"connect failed: {str(exc).strip()[:120]}"))
            continue
        try:
            cur = probe.cursor()
            cur.execute(
                "SELECT TABLE_SCHEMA FROM INFORMATION_SCHEMA.TABLES "
                "WHERE TABLE_NAME = 'K12Enrollment' AND TABLE_TYPE = 'BASE TABLE'"
            )
            row = cur.fetchone()
            cur.close()
            if row:
                report.append((database, f"found in schema [{row[0]}]"))
                if found == (None, None):
                    found = (database, row[0])
            else:
                report.append((database, "connected, no K12Enrollment table"))
        finally:
            probe.close()
    return found[0], found[1], report


def diagnose_server(args):
    lines = []
    try:
        probe = connect(args, "master")
    except pymssql.Error as exc:
        return [
            f"Cannot connect to server {args.host}:{args.port} as {args.user}: {str(exc).strip()[:200]}"
        ]
    try:
        cur = probe.cursor()
        cur.execute("SELECT name FROM sys.databases ORDER BY name")
        databases = [r[0] for r in cur.fetchall()]
        cur.close()
        lines.append(f"Server reachable. Databases present: {', '.join(databases)}")
    finally:
        probe.close()

    for database in databases:
        if database in ("master", "tempdb", "model", "msdb"):
            continue
        try:
            probe = connect(args, database)
        except pymssql.Error as exc:
            lines.append(f"  [{database}] connect failed: {str(exc).strip()[:120]}")
            continue
        try:
            cur = probe.cursor()
            cur.execute(
                "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE'"
            )
            table_count = cur.fetchone()[0]
            cur.execute(
                "SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES "
                "WHERE TABLE_NAME = 'K12Enrollment'"
            )
            hit = cur.fetchall()
            cur.close()
            where = ", ".join(f"[{s}].[{t}]" for s, t in hit) if hit else "not present"
            lines.append(f"  [{database}] {table_count} tables; K12Enrollment: {where}")
        finally:
            probe.close()
    return lines


def staging_row_count(args, database, schema):
    probe = connect(args, database)
    try:
        cur = probe.cursor()
        cur.execute(f"SELECT COUNT(*) FROM {qualified(schema, 'K12Enrollment')}")
        count = cur.fetchone()[0]
        cur.close()
        return count
    finally:
        probe.close()


def main():
    parser = argparse.ArgumentParser(
        description="Seed CIID Generate staging tables with synthetic IDEA data."
    )
    parser.add_argument(
        "--host", default=os.environ.get("MSSQL_HOST", "generate-mssql")
    )
    parser.add_argument(
        "--port", type=int, default=int(os.environ.get("MSSQL_PORT", "1433"))
    )
    parser.add_argument("--user", default=os.environ.get("MSSQL_USER", "sa"))
    parser.add_argument(
        "--password",
        default=os.environ.get(
            "MSSQL_SA_PASSWORD", os.environ.get("MSSQL_PASSWORD", "")
        ),
    )
    parser.add_argument(
        "--database", default=os.environ.get("MSSQL_DATABASE", "Generate")
    )
    parser.add_argument("--schema", default="Staging")
    parser.add_argument("--school-year", type=int, default=2025)
    parser.add_argument("--leas", type=int, default=5)
    parser.add_argument("--schools", type=int, default=20)
    parser.add_argument("--students", type=int, default=500)
    parser.add_argument("--idea-rate", type=float, default=1.0)
    parser.add_argument("--with-courses", action="store_true")
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--truncate", action="store_true")
    parser.add_argument("--autodiscover", action="store_true")
    parser.add_argument("--candidate-dbs", default="Staging,Generate,ODS,RDS")
    parser.add_argument("--skip-if-populated", action="store_true")
    args = parser.parse_args()

    if not args.password:
        print(
            "No SA password provided. Set MSSQL_SA_PASSWORD or pass --password.",
            file=sys.stderr,
        )
        sys.exit(2)
    if args.seed is not None:
        random.seed(args.seed)
        if _faker:
            Faker.seed(args.seed)

    run_dt = datetime.now().replace(microsecond=0)

    database, schema = args.database, args.schema
    if args.autodiscover:
        candidates = [c.strip() for c in args.candidate_dbs.split(",") if c.strip()]
        database, schema, report = find_staging_location(args, candidates)
        for db, status in report:
            print(f"  candidate [{db}]: {status}")
        if not database:
            print(
                f"Could not locate Staging.K12Enrollment in any of: {candidates}",
                file=sys.stderr,
            )
            print("Server diagnosis:", file=sys.stderr)
            for line in diagnose_server(args):
                print(line, file=sys.stderr)
            sys.exit(3)
        print(f"Discovered staging tables in [{database}].[{schema}]")

    if args.skip_if_populated:
        existing = staging_row_count(args, database, schema)
        if existing > 0:
            print(
                f"{schema}.K12Enrollment already has {existing} rows in [{database}]; nothing to do."
            )
            return

    organizations = build_organizations(
        args.leas, args.schools, args.school_year, run_dt
    )
    enrollments, races, disabilities, sped = build_students(
        args.students, organizations, args.school_year, args.idea_rate, run_dt
    )

    conn = connect(args, database)
    cursor = conn.cursor()

    target_tables = [
        "Organization",
        "K12Enrollment",
        "PersonRace",
        "PrimaryDisability",
        "ProgramParticipationSpecialEducation",
    ]
    if args.with_courses:
        target_tables.append("StudentCourse")

    try:
        if args.truncate:
            for table in target_tables:
                cursor.execute(f"DELETE FROM {qualified(schema, table)}")

        counts = {}
        counts["Organization"] = insert_many(
            cursor,
            schema,
            "Organization",
            [
                "LEA_Identifier_State",
                "LEA_Identifier_NCES",
                "LEA_SupervisoryUnionIdentificationNumber",
                "LEA_Name",
                "LEA_WebSiteAddress",
                "LEA_OperationalStatus",
                "LEA_UpdatedOperationalStatusEffectiveDate",
                "LEA_CharterLeaStatus",
                "LEA_CharterSchoolIndicator",
                "LEA_Type",
                "School_Identifier_State",
                "School_Identifier_NCES",
                "School_Name",
                "School_WebSiteAddress",
                "School_OperationalStatus",
                "School_UpdatedOperationalStatusEffectiveDate",
                "School_Type",
                "School_MagnetOrSpecialProgramEmphasisSchool",
                "School_SharedTimeIndicator",
                "School_VirtualSchoolStatus",
                "School_NationalSchoolLunchProgramStatus",
                "School_ReconstitutedStatus",
                "School_CharterSchoolIndicator",
                "School_StatePovertyDesignation",
                "SchoolImprovementAllocation",
                "SchoolYear",
                "RunDateTime",
            ],
            organizations,
        )
        counts["K12Enrollment"] = insert_many(
            cursor,
            schema,
            "K12Enrollment",
            [
                "Student_Identifier_State",
                "LEA_Identifier_State",
                "School_Identifier_State",
                "FirstName",
                "LastName",
                "MiddleName",
                "Birthdate",
                "Sex",
                "HispanicLatinoEthnicity",
                "EnrollmentEntryDate",
                "EnrollmentExitDate",
                "ExitOrWithdrawalType",
                "GradeLevel",
                "SchoolYear",
                "NumberOfSchoolDays",
                "NumberOfDaysAbsent",
                "AttendanceRate",
                "RunDateTime",
            ],
            enrollments,
        )
        counts["PersonRace"] = insert_many(
            cursor,
            schema,
            "PersonRace",
            [
                "Student_Identifier_State",
                "Lea_Identifier_State",
                "School_Identifier_State",
                "RaceType",
                "RecordStartDateTime",
                "RunDateTime",
            ],
            races,
        )
        counts["PrimaryDisability"] = insert_many(
            cursor,
            schema,
            "PrimaryDisability",
            [
                "Student_Identifier_State",
                "DisabilityType",
                "RecordStartDateTime",
                "RecordEndDateTime",
                "RunDateTime",
            ],
            disabilities,
        )
        counts["ProgramParticipationSpecialEducation"] = insert_many(
            cursor,
            schema,
            "ProgramParticipationSpecialEducation",
            [
                "Student_Identifier_State",
                "LEA_Identifier_State",
                "School_Identifier_State",
                "ProgramParticipationBeginDate",
                "ProgramParticipationEndDate",
                "SpecialEducationExitReason",
                "IDEAEducationalEnvironmentForEarlyChildhood",
                "IDEAEducationalEnvironmentForSchoolAge",
                "RunDateTime",
            ],
            sped,
        )

        if args.with_courses:
            courses = []
            subjects = ["MATH101", "ENG101", "SCI101", "HIST101", "PE101", "ART101"]
            for enr in enrollments:
                for course in random.sample(subjects, random.randint(2, 4)):
                    courses.append(
                        (
                            enr[0],
                            enr[1],
                            enr[2],
                            args.school_year,
                            course,
                            enr[12],
                            run_dt,
                        )
                    )
            counts["StudentCourse"] = insert_many(
                cursor,
                schema,
                "StudentCourse",
                [
                    "Student_Identifier_State",
                    "LEA_Identifier_State",
                    "School_Identifier_State",
                    "SchoolYear",
                    "CourseCode",
                    "CourseGradeLevel",
                    "RunDateTime",
                ],
                courses,
            )

        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()

    print(f"Run timestamp: {run_dt}")
    print(f"School year:   {args.school_year}")
    for table in target_tables:
        print(f"  [{database}].{schema}.{table}: {counts.get(table, 0)} rows")


if __name__ == "__main__":
    main()
