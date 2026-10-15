-- =====================================================================
--  seed.sql  (اختياري)  —  بيانات تجريبية عشان الموقع ميبقاش فاضي
--  شغّله بعد schema.sql. المواد دي أمثلة: عدّلها أو امسحها من لوحة التحكم.
-- =====================================================================
do $$
declare
  s_ped uuid;
  s_pnp uuid;
  l uuid;
begin
  -- مواد الفرقة الثالثة (الترم الأول)
  insert into subjects (name, year, term, icon) values ('Pediatrics', 3, 1, 'baby') returning id into s_ped;
  insert into subjects (name, year, term, icon) values ('Pediatric Nursing', 3, 1, 'baby');
  insert into subjects (name, year, term, icon) values ('Pediatric Nursing Practical', 3, 1, 'baby') returning id into s_pnp;
  insert into subjects (name, year, term, icon) values ('Pediatric Surgery', 3, 1, 'cut');

  -- مواد أمثلة لباقي الفرق (بدون محتوى)
  insert into subjects (name, year, term) values
    ('Anatomy', 1, 1), ('Physiology', 1, 1), ('Fundamentals of Nursing', 1, 1),
    ('Microbiology', 1, 2), ('Biochemistry', 1, 2), ('Nutrition', 1, 2),
    ('Medical-Surgical Nursing 1', 2, 1), ('Pharmacology', 2, 1), ('Pathology', 2, 1),
    ('Medical-Surgical Nursing 2', 2, 2), ('Health Assessment', 2, 2), ('Nursing Ethics', 2, 2),
    ('Maternity and Newborn Nursing', 3, 2), ('Gynecological Nursing', 3, 2), ('Psychiatric Nursing', 3, 2),
    ('Critical Care Nursing', 4, 1), ('Community Health Nursing', 4, 1), ('Nursing Administration', 4, 1),
    ('Geriatric Nursing', 4, 2), ('Emergency Nursing', 4, 2), ('Nursing Research', 4, 2);

  -- محاضرة 1
  insert into lectures (subject_id, title, lecture_date, explained, summary) values (
    s_ped, 'Hemolytic anemia', current_date, true,
    array[
      'Hemolytic anemia = red blood cells are destroyed faster than the bone marrow can replace them.',
      'Common signs: pallor, jaundice, fatigue, dark urine, splenomegaly.',
      'Labs: low Hb, high reticulocyte count, high indirect bilirubin.',
      'Examples: sickle cell disease, thalassemia, G6PD deficiency, autoimmune hemolytic anemia.'
    ]
  ) returning id into l;

  insert into questions (lecture_id, body, options, answer, explanation) values
    (l, 'Which laboratory finding is typical in hemolytic anemia?',
        '["Low reticulocyte count","Elevated reticulocyte count","Low indirect bilirubin","High serum haptoglobin"]'::jsonb, 1,
        'The bone marrow responds to RBC destruction by releasing more immature cells, so the reticulocyte count rises.'),
    (l, 'The priority nursing intervention during a sickle cell crisis is:',
        '["Restrict fluids","Apply cold packs","Give IV fluids and analgesics","Encourage strenuous exercise"]'::jsonb, 2,
        'Hydration reduces sickling and pain control is essential. Cold can worsen vasoconstriction.'),
    (l, 'A child with hemolytic anemia is most likely to show which skin sign?',
        '["Jaundice","Cyanosis only","Petechiae only","Erythema"]'::jsonb, 0,
        'Breakdown of RBCs raises indirect bilirubin, producing jaundice.');

  -- محاضرة 2
  insert into lectures (subject_id, title, lecture_date, explained, summary) values (
    s_pnp, 'Suction', current_date, true,
    array[
      'Pre-oxygenate (hyperoxygenate) before suctioning.',
      'Apply suction only while withdrawing the catheter, rotating gently.',
      'Each pass: no more than 10 seconds.',
      'Catheter size: no more than half the diameter of the airway.',
      'Stop and give oxygen if bradycardia or cyanosis occurs.'
    ]
  ) returning id into l;

  insert into questions (lecture_id, body, options, answer, explanation) values
    (l, 'Each suction pass should last no more than:',
        '["10 seconds","30 seconds","1 minute","2 minutes"]'::jsonb, 0,
        'Longer passes cause hypoxia, especially in children.'),
    (l, 'When should suction be applied?',
        '["While inserting the catheter","While withdrawing the catheter","Continuously throughout","Before opening the package"]'::jsonb, 1,
        'Suction during insertion damages the mucosa and removes oxygen.'),
    (l, 'Which action is correct if the child develops bradycardia during suctioning?',
        '["Continue quickly","Stop and give oxygen","Increase the pressure","Leave the room"]'::jsonb, 1,
        'Bradycardia signals hypoxia: stop, oxygenate, reassess.'),
    (l, 'The suction catheter should be no larger than:',
        '["The full airway diameter","Half the airway diameter","Twice the airway diameter","Any size is fine"]'::jsonb, 1,
        'A smaller catheter allows air to pass around it during suction.');
end $$;
