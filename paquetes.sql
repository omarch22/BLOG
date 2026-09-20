
-- Toda la lógica del blog vesta aqui...
--
-- Convención de errores (RAISE_APPLICATION_ERROR):
--   -20001  valor duplicado (email, nombre de etiqueta, ...)
--   -20002  el registro no existe
--   -20004  referencia a un registro padre inexistente
--   -20010  validación de datos de entrada


-- ---------------------------------------------------------------------
-- Función auxiliar: convierte un nombre en un "slug" para URL
--   'Bases de Datos Avanzadas' -> 'bases-de-datos-avanzadas'
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION slugify(p_text IN VARCHAR2) RETURN VARCHAR2 DETERMINISTIC IS
  v_slug VARCHAR2(400);
BEGIN
  v_slug := TRANSLATE(LOWER(TRIM(p_text)), 'áéíóúüñàèìòù', 'aeiouunaeiou');
  v_slug := REGEXP_REPLACE(v_slug, '[^a-z0-9]+', '-');
  v_slug := TRIM(BOTH '-' FROM v_slug);
  RETURN v_slug;
END slugify;
/

-- =====================================================================
-- PKG_USERS
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_users AS
  PROCEDURE add_user    (p_name  IN users.name%TYPE,
                         p_email IN users.email%TYPE,
                         p_id    OUT users.id%TYPE);
  PROCEDURE update_user (p_id    IN users.id%TYPE,
                         p_name  IN users.name%TYPE,
                         p_email IN users.email%TYPE);
  PROCEDURE delete_user (p_id    IN users.id%TYPE);
  FUNCTION  get_user    (p_id    IN users.id%TYPE) RETURN SYS_REFCURSOR;
  FUNCTION  list_users  RETURN SYS_REFCURSOR;
  FUNCTION  count_articles (p_id IN users.id%TYPE) RETURN NUMBER;
END pkg_users;
/

CREATE OR REPLACE PACKAGE BODY pkg_users AS

  -- Validación común a alta y modificación
  PROCEDURE validate (p_name IN VARCHAR2, p_email IN VARCHAR2) IS
  BEGIN
    IF TRIM(p_name) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'El nombre es obligatorio');
    END IF;
    IF p_email IS NULL
       OR NOT REGEXP_LIKE(TRIM(p_email), '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') THEN
      RAISE_APPLICATION_ERROR(-20010, 'El email no tiene un formato válido');
    END IF;
  END validate;

  PROCEDURE add_user (p_name  IN users.name%TYPE,
                      p_email IN users.email%TYPE,
                      p_id    OUT users.id%TYPE) IS
  BEGIN
    validate(p_name, p_email);
    INSERT INTO users (name, email)
    VALUES (TRIM(p_name), LOWER(TRIM(p_email)))
    RETURNING id INTO p_id;
    COMMIT;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20001, 'Ya existe un usuario con ese email');
  END add_user;

  PROCEDURE update_user (p_id    IN users.id%TYPE,
                         p_name  IN users.name%TYPE,
                         p_email IN users.email%TYPE) IS
  BEGIN
    validate(p_name, p_email);
    UPDATE users
       SET name = TRIM(p_name), email = LOWER(TRIM(p_email))
     WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'El usuario no existe');
    END IF;
    COMMIT;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20001, 'Ya existe otro usuario con ese email');
  END update_user;

  -- Borra también sus artículos y comentarios (ON DELETE CASCADE)
  PROCEDURE delete_user (p_id IN users.id%TYPE) IS
  BEGIN
    DELETE FROM users WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'El usuario no existe');
    END IF;
    COMMIT;
  END delete_user;

  FUNCTION get_user (p_id IN users.id%TYPE) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT id, name, email FROM users WHERE id = p_id;
    RETURN v_cur;
  END get_user;

  FUNCTION list_users RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT u.id, u.name, u.email,
             (SELECT COUNT(*) FROM articles a WHERE a.user_id = u.id) AS n_articles,
             (SELECT COUNT(*) FROM comments c WHERE c.user_id = u.id) AS n_comments
        FROM users u
       ORDER BY u.id;
    RETURN v_cur;
  END list_users;

  FUNCTION count_articles (p_id IN users.id%TYPE) RETURN NUMBER IS
    v_total NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_total FROM articles WHERE user_id = p_id;
    RETURN v_total;
  END count_articles;

END pkg_users;
/

-- =====================================================================
-- PKG_TAGS
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_tags AS
  -- Si p_url es NULL se genera a partir del nombre (slugify)
  PROCEDURE add_tag    (p_name IN tags.name%TYPE,
                        p_url  IN tags.url%TYPE,
                        p_id   OUT tags.id%TYPE);
  PROCEDURE update_tag (p_id   IN tags.id%TYPE,
                        p_name IN tags.name%TYPE,
                        p_url  IN tags.url%TYPE);
  PROCEDURE delete_tag (p_id   IN tags.id%TYPE);
  FUNCTION  get_tag    (p_id   IN tags.id%TYPE) RETURN SYS_REFCURSOR;
  FUNCTION  list_tags  RETURN SYS_REFCURSOR;
  FUNCTION  count_articles (p_id IN tags.id%TYPE) RETURN NUMBER;
END pkg_tags;
/

CREATE OR REPLACE PACKAGE BODY pkg_tags AS

  PROCEDURE add_tag (p_name IN tags.name%TYPE,
                     p_url  IN tags.url%TYPE,
                     p_id   OUT tags.id%TYPE) IS
    v_url tags.url%TYPE;
  BEGIN
    IF TRIM(p_name) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'El nombre es obligatorio');
    END IF;
    v_url := NVL(TRIM(p_url), slugify(p_name));
    IF v_url IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'No se pudo generar la URL; indícala manualmente');
    END IF;
    INSERT INTO tags (name, url) VALUES (TRIM(p_name), v_url)
    RETURNING id INTO p_id;
    COMMIT;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20001, 'Ya existe una etiqueta con ese nombre o URL');
  END add_tag;

  PROCEDURE update_tag (p_id   IN tags.id%TYPE,
                        p_name IN tags.name%TYPE,
                        p_url  IN tags.url%TYPE) IS
    v_url tags.url%TYPE;
  BEGIN
    IF TRIM(p_name) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'El nombre es obligatorio');
    END IF;
    v_url := NVL(TRIM(p_url), slugify(p_name));
    IF v_url IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'No se pudo generar la URL; indícala manualmente');
    END IF;
    UPDATE tags SET name = TRIM(p_name), url = v_url WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'La etiqueta no existe');
    END IF;
    COMMIT;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20001, 'Ya existe otra etiqueta con ese nombre o URL');
  END update_tag;

  PROCEDURE delete_tag (p_id IN tags.id%TYPE) IS
  BEGIN
    DELETE FROM tags WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'La etiqueta no existe');
    END IF;
    COMMIT;
  END delete_tag;

  FUNCTION get_tag (p_id IN tags.id%TYPE) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR SELECT id, name, url FROM tags WHERE id = p_id;
    RETURN v_cur;
  END get_tag;

  FUNCTION list_tags RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT t.id, t.name, t.url,
             (SELECT COUNT(*) FROM article_tags x WHERE x.tag_id = t.id) AS n_articles
        FROM tags t
       ORDER BY t.name;
    RETURN v_cur;
  END list_tags;

  FUNCTION count_articles (p_id IN tags.id%TYPE) RETURN NUMBER IS
    v_total NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_total FROM article_tags WHERE tag_id = p_id;
    RETURN v_total;
  END count_articles;

END pkg_tags;
/

-- =====================================================================
-- PKG_CATEGORIES
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_categories AS
  PROCEDURE add_category    (p_name IN categories.name%TYPE,
                             p_url  IN categories.url%TYPE,
                             p_id   OUT categories.id%TYPE);
  PROCEDURE update_category (p_id   IN categories.id%TYPE,
                             p_name IN categories.name%TYPE,
                             p_url  IN categories.url%TYPE);
  PROCEDURE delete_category (p_id   IN categories.id%TYPE);
  FUNCTION  get_category    (p_id   IN categories.id%TYPE) RETURN SYS_REFCURSOR;
  FUNCTION  list_categories RETURN SYS_REFCURSOR;
  FUNCTION  count_articles  (p_id   IN categories.id%TYPE) RETURN NUMBER;
END pkg_categories;
/

CREATE OR REPLACE PACKAGE BODY pkg_categories AS

  PROCEDURE add_category (p_name IN categories.name%TYPE,
                          p_url  IN categories.url%TYPE,
                          p_id   OUT categories.id%TYPE) IS
    v_url categories.url%TYPE;
  BEGIN
    IF TRIM(p_name) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'El nombre es obligatorio');
    END IF;
    v_url := NVL(TRIM(p_url), slugify(p_name));
    IF v_url IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'No se pudo generar la URL; indícala manualmente');
    END IF;
    INSERT INTO categories (name, url) VALUES (TRIM(p_name), v_url)
    RETURNING id INTO p_id;
    COMMIT;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20001, 'Ya existe una categoría con ese nombre o URL');
  END add_category;

  PROCEDURE update_category (p_id   IN categories.id%TYPE,
                             p_name IN categories.name%TYPE,
                             p_url  IN categories.url%TYPE) IS
    v_url categories.url%TYPE;
  BEGIN
    IF TRIM(p_name) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'El nombre es obligatorio');
    END IF;
    v_url := NVL(TRIM(p_url), slugify(p_name));
    IF v_url IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'No se pudo generar la URL; indícala manualmente');
    END IF;
    UPDATE categories SET name = TRIM(p_name), url = v_url WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'La categoría no existe');
    END IF;
    COMMIT;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20001, 'Ya existe otra categoría con ese nombre o URL');
  END update_category;

  PROCEDURE delete_category (p_id IN categories.id%TYPE) IS
  BEGIN
    DELETE FROM categories WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'La categoría no existe');
    END IF;
    COMMIT;
  END delete_category;

  FUNCTION get_category (p_id IN categories.id%TYPE) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR SELECT id, name, url FROM categories WHERE id = p_id;
    RETURN v_cur;
  END get_category;

  FUNCTION list_categories RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT c.id, c.name, c.url,
             (SELECT COUNT(*) FROM article_categories x WHERE x.category_id = c.id) AS n_articles
        FROM categories c
       ORDER BY c.name;
    RETURN v_cur;
  END list_categories;

  FUNCTION count_articles (p_id IN categories.id%TYPE) RETURN NUMBER IS
    v_total NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_total FROM article_categories WHERE category_id = p_id;
    RETURN v_total;
  END count_articles;

END pkg_categories;
/

-- =====================================================================
-- PKG_ARTICLES
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_articles AS
  PROCEDURE add_article    (p_title   IN articles.title%TYPE,
                            p_content IN articles.content%TYPE,
                            p_user_id IN articles.user_id%TYPE,
                            p_id      OUT articles.id%TYPE);
  PROCEDURE update_article (p_id      IN articles.id%TYPE,
                            p_title   IN articles.title%TYPE,
                            p_content IN articles.content%TYPE);
  PROCEDURE delete_article (p_id      IN articles.id%TYPE);

  -- Etiquetas y categorías de un artículo (relaciones N-N)
  PROCEDURE add_tag         (p_article_id IN articles.id%TYPE, p_tag_id      IN tags.id%TYPE);
  PROCEDURE remove_tag      (p_article_id IN articles.id%TYPE, p_tag_id      IN tags.id%TYPE);
  PROCEDURE add_category    (p_article_id IN articles.id%TYPE, p_category_id IN categories.id%TYPE);
  PROCEDURE remove_category (p_article_id IN articles.id%TYPE, p_category_id IN categories.id%TYPE);

  -- Consultas (devuelven REF CURSOR)
  FUNCTION get_article      (p_id          IN articles.id%TYPE)    RETURN SYS_REFCURSOR;
  FUNCTION list_articles    RETURN SYS_REFCURSOR;
  FUNCTION list_by_user     (p_user_id     IN users.id%TYPE)       RETURN SYS_REFCURSOR;
  FUNCTION list_by_tag      (p_tag_id      IN tags.id%TYPE)        RETURN SYS_REFCURSOR;
  FUNCTION list_by_category (p_category_id IN categories.id%TYPE)  RETURN SYS_REFCURSOR;
  FUNCTION search_articles  (p_text        IN VARCHAR2)            RETURN SYS_REFCURSOR;
  FUNCTION get_tags         (p_article_id  IN articles.id%TYPE)    RETURN SYS_REFCURSOR;
  FUNCTION get_categories   (p_article_id  IN articles.id%TYPE)    RETURN SYS_REFCURSOR;

  -- Función escalar
  FUNCTION count_comments   (p_article_id  IN articles.id%TYPE)    RETURN NUMBER;
END pkg_articles;
/

CREATE OR REPLACE PACKAGE BODY pkg_articles AS

  e_no_parent EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_no_parent, -2291);   -- ORA-02291: clave padre no encontrada

  PROCEDURE validate (p_title IN VARCHAR2, p_content IN CLOB) IS
  BEGIN
    IF TRIM(p_title) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'El título es obligatorio');
    END IF;
    IF p_content IS NULL OR DBMS_LOB.GETLENGTH(p_content) = 0 THEN
      RAISE_APPLICATION_ERROR(-20010, 'El contenido es obligatorio');
    END IF;
  END validate;

  PROCEDURE add_article (p_title   IN articles.title%TYPE,
                         p_content IN articles.content%TYPE,
                         p_user_id IN articles.user_id%TYPE,
                         p_id      OUT articles.id%TYPE) IS
  BEGIN
    validate(p_title, p_content);
    INSERT INTO articles (title, content, user_id)
    VALUES (TRIM(p_title), p_content, p_user_id)
    RETURNING id INTO p_id;
    COMMIT;
  EXCEPTION
    WHEN e_no_parent THEN
      RAISE_APPLICATION_ERROR(-20004, 'El usuario indicado no existe');
  END add_article;

  PROCEDURE update_article (p_id      IN articles.id%TYPE,
                            p_title   IN articles.title%TYPE,
                            p_content IN articles.content%TYPE) IS
  BEGIN
    validate(p_title, p_content);
    UPDATE articles
       SET title = TRIM(p_title), content = p_content
     WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'El artículo no existe');
    END IF;
    COMMIT;
  END update_article;

  -- Borra también sus comentarios y vínculos con etiquetas/categorías
  PROCEDURE delete_article (p_id IN articles.id%TYPE) IS
  BEGIN
    DELETE FROM articles WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'El artículo no existe');
    END IF;
    COMMIT;
  END delete_article;

  -- ---------- Etiquetas ----------
  PROCEDURE add_tag (p_article_id IN articles.id%TYPE, p_tag_id IN tags.id%TYPE) IS
  BEGIN
    INSERT INTO article_tags (article_id, tag_id) VALUES (p_article_id, p_tag_id);
    COMMIT;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20001, 'El artículo ya tiene esa etiqueta');
    WHEN e_no_parent THEN
      RAISE_APPLICATION_ERROR(-20004, 'El artículo o la etiqueta no existe');
  END add_tag;

  PROCEDURE remove_tag (p_article_id IN articles.id%TYPE, p_tag_id IN tags.id%TYPE) IS
  BEGIN
    DELETE FROM article_tags WHERE article_id = p_article_id AND tag_id = p_tag_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'El artículo no tiene esa etiqueta');
    END IF;
    COMMIT;
  END remove_tag;

  -- ---------- Categorías ----------
  PROCEDURE add_category (p_article_id IN articles.id%TYPE, p_category_id IN categories.id%TYPE) IS
  BEGIN
    INSERT INTO article_categories (article_id, category_id) VALUES (p_article_id, p_category_id);
    COMMIT;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20001, 'El artículo ya tiene esa categoría');
    WHEN e_no_parent THEN
      RAISE_APPLICATION_ERROR(-20004, 'El artículo o la categoría no existe');
  END add_category;

  PROCEDURE remove_category (p_article_id IN articles.id%TYPE, p_category_id IN categories.id%TYPE) IS
  BEGIN
    DELETE FROM article_categories WHERE article_id = p_article_id AND category_id = p_category_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'El artículo no tiene esa categoría');
    END IF;
    COMMIT;
  END remove_category;

  -- ---------- Consultas ----------
  FUNCTION get_article (p_id IN articles.id%TYPE) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT a.id, a.title, a.article_date, a.content, u.name AS author,
             (SELECT COUNT(*) FROM comments c WHERE c.article_id = a.id) AS n_comments
        FROM articles a
        JOIN users u ON u.id = a.user_id
       WHERE a.id = p_id;
    RETURN v_cur;
  END get_article;

  FUNCTION list_articles RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT a.id, a.title, a.article_date, u.name AS author,
             (SELECT COUNT(*) FROM comments c WHERE c.article_id = a.id) AS n_comments
        FROM articles a
        JOIN users u ON u.id = a.user_id
       ORDER BY a.article_date DESC, a.id DESC;
    RETURN v_cur;
  END list_articles;

  FUNCTION list_by_user (p_user_id IN users.id%TYPE) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT a.id, a.title, a.article_date, u.name AS author,
             (SELECT COUNT(*) FROM comments c WHERE c.article_id = a.id) AS n_comments
        FROM articles a
        JOIN users u ON u.id = a.user_id
       WHERE a.user_id = p_user_id
       ORDER BY a.article_date DESC, a.id DESC;
    RETURN v_cur;
  END list_by_user;

  FUNCTION list_by_tag (p_tag_id IN tags.id%TYPE) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT a.id, a.title, a.article_date, u.name AS author,
             (SELECT COUNT(*) FROM comments c WHERE c.article_id = a.id) AS n_comments
        FROM articles a
        JOIN users u ON u.id = a.user_id
        JOIN article_tags atg ON atg.article_id = a.id
       WHERE atg.tag_id = p_tag_id
       ORDER BY a.article_date DESC, a.id DESC;
    RETURN v_cur;
  END list_by_tag;

  FUNCTION list_by_category (p_category_id IN categories.id%TYPE) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT a.id, a.title, a.article_date, u.name AS author,
             (SELECT COUNT(*) FROM comments c WHERE c.article_id = a.id) AS n_comments
        FROM articles a
        JOIN users u ON u.id = a.user_id
        JOIN article_categories acg ON acg.article_id = a.id
       WHERE acg.category_id = p_category_id
       ORDER BY a.article_date DESC, a.id DESC;
    RETURN v_cur;
  END list_by_category;

  FUNCTION search_articles (p_text IN VARCHAR2) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT a.id, a.title, a.article_date, u.name AS author,
             (SELECT COUNT(*) FROM comments c WHERE c.article_id = a.id) AS n_comments
        FROM articles a
        JOIN users u ON u.id = a.user_id
       WHERE UPPER(a.title)   LIKE '%' || UPPER(p_text) || '%'
          OR UPPER(a.content) LIKE '%' || UPPER(p_text) || '%'
       ORDER BY a.article_date DESC, a.id DESC;
    RETURN v_cur;
  END search_articles;

  FUNCTION get_tags (p_article_id IN articles.id%TYPE) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT t.id, t.name, t.url
        FROM tags t
        JOIN article_tags atg ON atg.tag_id = t.id
       WHERE atg.article_id = p_article_id
       ORDER BY t.name;
    RETURN v_cur;
  END get_tags;

  FUNCTION get_categories (p_article_id IN articles.id%TYPE) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT c.id, c.name, c.url
        FROM categories c
        JOIN article_categories acg ON acg.category_id = c.id
       WHERE acg.article_id = p_article_id
       ORDER BY c.name;
    RETURN v_cur;
  END get_categories;

  FUNCTION count_comments (p_article_id IN articles.id%TYPE) RETURN NUMBER IS
    v_total NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_total FROM comments WHERE article_id = p_article_id;
    RETURN v_total;
  END count_comments;

END pkg_articles;
/

-- =====================================================================
-- PKG_COMMENTS
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_comments AS
  PROCEDURE add_comment    (p_name       IN comments.name%TYPE,
                            p_url        IN comments.url%TYPE,
                            p_user_id    IN comments.user_id%TYPE,
                            p_article_id IN comments.article_id%TYPE,
                            p_id         OUT comments.id%TYPE);
  PROCEDURE update_comment (p_id   IN comments.id%TYPE,
                            p_name IN comments.name%TYPE,
                            p_url  IN comments.url%TYPE);
  PROCEDURE delete_comment (p_id   IN comments.id%TYPE);
  FUNCTION  get_comment      (p_id         IN comments.id%TYPE)         RETURN SYS_REFCURSOR;
  FUNCTION  list_by_article  (p_article_id IN articles.id%TYPE)         RETURN SYS_REFCURSOR;
  FUNCTION  list_by_user     (p_user_id    IN users.id%TYPE)            RETURN SYS_REFCURSOR;
END pkg_comments;
/

CREATE OR REPLACE PACKAGE BODY pkg_comments AS

  e_no_parent EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_no_parent, -2291);

  PROCEDURE add_comment (p_name       IN comments.name%TYPE,
                         p_url        IN comments.url%TYPE,
                         p_user_id    IN comments.user_id%TYPE,
                         p_article_id IN comments.article_id%TYPE,
                         p_id         OUT comments.id%TYPE) IS
  BEGIN
    IF TRIM(p_name) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'El comentario no puede estar vacío');
    END IF;
    INSERT INTO comments (name, url, user_id, article_id)
    VALUES (TRIM(p_name), TRIM(p_url), p_user_id, p_article_id)
    RETURNING id INTO p_id;
    COMMIT;
  EXCEPTION
    WHEN e_no_parent THEN
      RAISE_APPLICATION_ERROR(-20004, 'El usuario o el artículo no existe');
  END add_comment;

  PROCEDURE update_comment (p_id   IN comments.id%TYPE,
                            p_name IN comments.name%TYPE,
                            p_url  IN comments.url%TYPE) IS
  BEGIN
    IF TRIM(p_name) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010, 'El comentario no puede estar vacío');
    END IF;
    UPDATE comments SET name = TRIM(p_name), url = TRIM(p_url) WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'El comentario no existe');
    END IF;
    COMMIT;
  END update_comment;

  PROCEDURE delete_comment (p_id IN comments.id%TYPE) IS
  BEGIN
    DELETE FROM comments WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'El comentario no existe');
    END IF;
    COMMIT;
  END delete_comment;

  FUNCTION get_comment (p_id IN comments.id%TYPE) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT c.id, c.name, c.url, c.user_id, c.article_id
        FROM comments c
       WHERE c.id = p_id;
    RETURN v_cur;
  END get_comment;

  FUNCTION list_by_article (p_article_id IN articles.id%TYPE) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT c.id, c.name, c.url, u.name AS author
        FROM comments c
        JOIN users u ON u.id = c.user_id
       WHERE c.article_id = p_article_id
       ORDER BY c.id;
    RETURN v_cur;
  END list_by_article;

  FUNCTION list_by_user (p_user_id IN users.id%TYPE) RETURN SYS_REFCURSOR IS
    v_cur SYS_REFCURSOR;
  BEGIN
    OPEN v_cur FOR
      SELECT c.id, c.name, c.url, c.article_id, a.title AS article
        FROM comments c
        JOIN articles a ON a.id = c.article_id
       WHERE c.user_id = p_user_id
       ORDER BY c.id;
    RETURN v_cur;
  END list_by_user;

END pkg_comments;
/

-- ---------------------------------------------------------------------
-- Comprobación: si compiló todo bien, esta consulta no devuelve filas
-- ---------------------------------------------------------------------
SELECT name, type, line, position, text
  FROM user_errors
 ORDER BY name, type, sequence;