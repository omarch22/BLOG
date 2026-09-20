
SET SERVEROUTPUT ON

DECLARE
  v_ana   NUMBER;  v_luis  NUMBER;
  v_art1  NUMBER;  v_art2  NUMBER;  v_art3 NUMBER;
  v_tag1  NUMBER;  v_tag2  NUMBER;  v_tag3 NUMBER;
  v_cat1  NUMBER;  v_cat2  NUMBER;
  v_com   NUMBER;
BEGIN
  -- Usuarios
  pkg_users.add_user('Ana García',  'ana@example.com',  v_ana);
  pkg_users.add_user('Luis Pérez',  'luis@example.com', v_luis);

  -- Etiquetas (URL automática a partir del nombre)
  pkg_tags.add_tag('Oracle', NULL, v_tag1);
  pkg_tags.add_tag('PL/SQL', NULL, v_tag2);
  pkg_tags.add_tag('Python', NULL, v_tag3);

  -- Categorías
  pkg_categories.add_category('Bases de datos', NULL, v_cat1);
  pkg_categories.add_category('Programación',   NULL, v_cat2);

  -- Artículos
  pkg_articles.add_article('Introducción a PL/SQL',
      'PL/SQL es la extensión procedimental de Oracle sobre SQL. Permite crear procedimientos, funciones y paquetes.',
      v_ana, v_art1);
  pkg_articles.add_article('Conectar Python con Oracle',
      'La librería oracledb permite llamar a procedimientos y funciones almacenados con callproc y callfunc.',
      v_ana, v_art2);
  pkg_articles.add_article('Paquetes frente a procedimientos sueltos',
      'Agrupar la lógica en paquetes mejora la organización, el rendimiento y el control de dependencias.',
      v_luis, v_art3);

  -- Relaciones N-N
  pkg_articles.add_tag(v_art1, v_tag1);
  pkg_articles.add_tag(v_art1, v_tag2);
  pkg_articles.add_tag(v_art2, v_tag1);
  pkg_articles.add_tag(v_art2, v_tag3);
  pkg_articles.add_tag(v_art3, v_tag2);

  pkg_articles.add_category(v_art1, v_cat1);
  pkg_articles.add_category(v_art2, v_cat1);
  pkg_articles.add_category(v_art2, v_cat2);
  pkg_articles.add_category(v_art3, v_cat1);

  -- Comentarios
  pkg_comments.add_comment('¡Muy útil, gracias!',       NULL,                     v_luis, v_art1, v_com);
  pkg_comments.add_comment('Me gustaría ver un ejemplo con cursores.',
                           'https://example.com/cursores',                        v_luis, v_art1, v_com);
  pkg_comments.add_comment('Buen resumen de oracledb.', NULL,                     v_ana,  v_art3, v_com);

  DBMS_OUTPUT.PUT_LINE('Datos de prueba cargados correctamente.');
  DBMS_OUTPUT.PUT_LINE('Comentarios del artículo 1: ' || pkg_articles.count_comments(v_art1));
END;
/