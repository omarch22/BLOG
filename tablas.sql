-- =====================================================================
-- 01_tablas.sql   (ejecutar conectado como BLOG)
-- Modelo del blog: users, articles, comments, tags, categories
-- + tablas intermedias article_tags y article_categories (relaciones N-N)
--
-- Nota: "date" y "text" del diagrama se llaman article_date y content
-- para evitar palabras delicadas de Oracle.
-- =====================================================================

-- Limpieza para poder relanzar el script
BEGIN
  FOR t IN (SELECT table_name
              FROM user_tables
             WHERE table_name IN ('ARTICLE_TAGS', 'ARTICLE_CATEGORIES', 'COMMENTS',
                                  'ARTICLES', 'TAGS', 'CATEGORIES', 'USERS'))
  LOOP
    EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

-- ---------------------------------------------------------------------
-- USERS
-- ---------------------------------------------------------------------
CREATE TABLE users (
  id     NUMBER GENERATED ALWAYS AS IDENTITY,
  name   VARCHAR2(100) NOT NULL,
  email  VARCHAR2(150) NOT NULL,
  CONSTRAINT pk_users       PRIMARY KEY (id),
  CONSTRAINT uq_users_email UNIQUE (email)
);

-- ---------------------------------------------------------------------
-- ARTICLES  (1 usuario -> N artículos)
-- ---------------------------------------------------------------------
CREATE TABLE articles (
  id            NUMBER GENERATED ALWAYS AS IDENTITY,
  title         VARCHAR2(200) NOT NULL,
  article_date  DATE DEFAULT SYSDATE NOT NULL,
  content       CLOB NOT NULL,
  user_id       NUMBER NOT NULL,
  CONSTRAINT pk_articles      PRIMARY KEY (id),
  CONSTRAINT fk_articles_user FOREIGN KEY (user_id)
      REFERENCES users (id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- COMMENTS  (1 usuario -> N comentarios, 1 artículo -> N comentarios)
-- ---------------------------------------------------------------------
CREATE TABLE comments (
  id          NUMBER GENERATED ALWAYS AS IDENTITY,
  name        VARCHAR2(1000) NOT NULL,
  url         VARCHAR2(300),
  user_id     NUMBER NOT NULL,
  article_id  NUMBER NOT NULL,
  CONSTRAINT pk_comments         PRIMARY KEY (id),
  CONSTRAINT fk_comments_user    FOREIGN KEY (user_id)
      REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_comments_article FOREIGN KEY (article_id)
      REFERENCES articles (id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- TAGS y CATEGORIES
-- ---------------------------------------------------------------------
CREATE TABLE tags (
  id    NUMBER GENERATED ALWAYS AS IDENTITY,
  name  VARCHAR2(100) NOT NULL,
  url   VARCHAR2(200) NOT NULL,
  CONSTRAINT pk_tags      PRIMARY KEY (id),
  CONSTRAINT uq_tags_name UNIQUE (name),
  CONSTRAINT uq_tags_url  UNIQUE (url)
);

CREATE TABLE categories (
  id    NUMBER GENERATED ALWAYS AS IDENTITY,
  name  VARCHAR2(100) NOT NULL,
  url   VARCHAR2(200) NOT NULL,
  CONSTRAINT pk_categories      PRIMARY KEY (id),
  CONSTRAINT uq_categories_name UNIQUE (name),
  CONSTRAINT uq_categories_url  UNIQUE (url)
);

-- ---------------------------------------------------------------------
-- Tablas intermedias (N-N)
-- ---------------------------------------------------------------------
CREATE TABLE article_tags (
  article_id  NUMBER NOT NULL,
  tag_id      NUMBER NOT NULL,
  CONSTRAINT pk_article_tags PRIMARY KEY (article_id, tag_id),
  CONSTRAINT fk_at_article   FOREIGN KEY (article_id)
      REFERENCES articles (id) ON DELETE CASCADE,
  CONSTRAINT fk_at_tag       FOREIGN KEY (tag_id)
      REFERENCES tags (id) ON DELETE CASCADE
);

CREATE TABLE article_categories (
  article_id   NUMBER NOT NULL,
  category_id  NUMBER NOT NULL,
  CONSTRAINT pk_article_categories PRIMARY KEY (article_id, category_id),
  CONSTRAINT fk_ac_article         FOREIGN KEY (article_id)
      REFERENCES articles (id) ON DELETE CASCADE,
  CONSTRAINT fk_ac_category        FOREIGN KEY (category_id)
      REFERENCES categories (id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- Índices sobre claves foráneas (las PK compuestas ya cubren article_id)
-- ---------------------------------------------------------------------
CREATE INDEX ix_articles_user      ON articles (user_id);
CREATE INDEX ix_comments_user      ON comments (user_id);
CREATE INDEX ix_comments_article   ON comments (article_id);
CREATE INDEX ix_article_tags_tag   ON article_tags (tag_id);
CREATE INDEX ix_article_cats_cat   ON article_categories (category_id);