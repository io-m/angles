import {
  OPERATOR_ADDRESS,
  OPERATOR_COUNTRY,
  OPERATOR_CVR,
  OPERATOR_LEGAL_FORM,
  OPERATOR_LEGAL_NAME,
} from '@/lib/legalOperator';

export function OperatorIdentity() {
  return (
    <>
      {OPERATOR_LEGAL_NAME}, an {OPERATOR_LEGAL_FORM} in {OPERATOR_COUNTRY},
      postal address {OPERATOR_ADDRESS}, CVR {OPERATOR_CVR}
    </>
  );
}

export function OperatorPostal() {
  return (
    <>
      {OPERATOR_LEGAL_NAME}
      <br />
      {OPERATOR_LEGAL_FORM}, {OPERATOR_COUNTRY}
      <br />
      {OPERATOR_ADDRESS}
      <br />
      CVR {OPERATOR_CVR}
    </>
  );
}
